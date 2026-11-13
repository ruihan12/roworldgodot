# RoWorld client UI extract

Source: RoWorld Luau at fork ruihan12/roworldgodot @ ae7a350 (AGPL-3.0), unpacked at /workspace/roworld_src. All refs are `path:line` in that tree. RoWorld's client is itself a port of an earlier Godot project ("Port of scripts/ui/*.gd" headers), so most sizes are Godot logical px on a 1600x900 design. That is the same canvas this project uses.

Nothing here changes the live UI. The rounded UI stays as it is. These are reference data and docs only.

## Generated files (ui_upstream/)

| file | what |
| --- | --- |
| theme.json | UITheme colour tokens (hex + rgba + line), spacing S1..S7, radii, font metrics, button variants, glass panel recipe, message-category colours/icons |
| theme_tokens.gd | the same tokens as GDScript `const Color(...)` (preload it) |
| number_format.json / number_format.gd | NumberFormat.luau + UITheme fmt_* rules, GDScript port (tests/test_ui_upstream.gd) |
| audio.json | 62 SFX names, 3 sound manifests (ids + lengths), logical-id map, fallbacks, cooldowns, throttles, max-same, priorities, auto-duck, pop rules, soundtrack (33 tracks, 6 moods), event -> sound routing |
| icons.json | 59 icon keys -> Roblox asset, repo PNG, res:// path in this project, and every call site |
| atlases.json | MapSprites (glyphs/plates/units/status cell layout and order), UiShapes radial segments (56), UIKit shadows, MapFx, rails, flags |
| catalog.json | build/nuke/arsenal kinds, hotkey order, titles, short names, blurbs, placement-fail reasons, bulk steps, ratio stops |
| hotkeys.json | keyboard map |
| map_palette.json | MapSurface terrain colours, ramps, territory alpha/border/highlight factors |
| strings_by_screen.json | 918 user-facing-looking literals (Dev harness excluded) grouped by module, with line numbers (heuristic filter) |
| colors_all.json, strings_all.json, sfx_callsites.json, icon_usage.json, constants_all.json, module_headers.json | raw mechanical scans (514 colour literals, 1226 strings, 151 sfx calls, 143 icon refs, 832 UPPER_CASE constants, 137 module headers) |

Regenerate: `python3 tools/extract_upstream_ui.py` then `python3 tools/extract_upstream_ui_curated.py` (the second reads icon_usage.json from the first).

## Design system (src/client/UI/UITheme.luau)

- Canvas 1600x900 (UITheme.luau:1305). Desktop scale is `clamp(min(vw/1600, vh/900), 0.75, 2.5)`, and touch uses `clamp(.., 1, 2)` (:1312). Compact (phone) layout applies when `vh < 560 or vw < 900` (UIRoot.luau:2202). The single-row command bar ("wide") needs `vw >= 1420 + extra` (UIRoot.luau:2211).
- Colours (:147-173):
  - Glass: GLASS #0d1326 @0.84, GLASS_SOLID #0b1020 @0.96, GLASS_RAISED #1a213d @0.94
  - Lines and fills: LINE white @0.10, LINE_2 @0.18, FILL @0.06, FILL_2 @0.11
  - Text: TEXT #f0f4ff, TEXT_2 #adbadb, TEXT_3 #7a87ab
  - Amber (primary actions): AMBER #ffb547, AMBER_HI #ffcc78, AMBER_LO #cc7d21
  - Accents: CYAN #4fd1ff (info), GREEN #5ee399, RED #ff5463, ORANGE #ff945c, VIOLET #b89eff, GOLD #ffd666
  - INK #1a1105 is the text colour on amber
  - Surrender red: #de303c, hi #f04852, lo #8c1420
- Spacing is an 8 px scale: S1..S7 = 4, 8, 12, 16, 24, 32, 48. Radii are R_SM 6, R_MD 10, R_LG 14, with 999 for pills (:176-185).
- Font is Rubik at weights 100-900. Line height is 1.185 em, ascent 0.935 em, and tabular digits are 0.975 wide (:207-270). The font file is not in the repo (Roblox font id 12187365977).
- Glass panel: navy tint plus GLASS_BOOST 0.08, a 1 px LINE border, a top sheen (0.045 gradient plus a sheen line) and a 9-slice soft shadow (GlassPanel.luau header; UIKit.luau shadows).
- Buttons (:1602-1760):
  - Glass/Ghost/Danger/Chip/Public variants are tints of FILL, RED or CYAN with LINE borders.
  - Primary is solid AMBER with a 3 px AMBER_LO bottom lip, radius 10, padding 22x10, INK text at weight 800, letter spacing 2, size 17.
  - Surrender is the same shape in SURRENDER_RED.
  - Chip is a 999-radius pill whose pressed state is an AMBER@0.2 fill with an AMBER border.
- Message categories (:1420-1455, Defs.luau:126-130):

| id | category | colour | icon |
| --- | --- | --- | --- |
| 0 | INFO | CYAN | info |
| 1 | GOOD | GREEN | crown |
| 2 | BAD | ORANGE | attack |
| 3 | ALERT | RED | target |
| 4 | ALLIANCE | VIOLET | alliance |

- Dark nation colours are lifted for UI use: luminance < 0.32 → `lerp(col, white, 0.32 - l + 0.1)` (:1457).

## Screens and panels

| screen / panel | module (lines) | where / layout | notes |
| --- | --- | --- | --- |
| Title screen | UI/TitleScreen.luau (1703) | over live attract-mode map | AIRFRONT gradient wordmark (per-glyph Rubik Heavy, shine sweep, drop shadow), Play Solo + difficulty chips, Multiplayer (server status), How to Play, credits, queue card |
| Map picker | UI/MapPicker.luau (340), UI/UIMaps.luau | modal grid of cards under category tabs | card: thumb, name, size; footer credits Natural Earth/NOAA; featured order world, europe, northamerica, southamerica, asia, africa (UIMaps.luau:11) |
| Spawn banner | UI/SpawnOverlay.luau (320) | top centre, one slim row | "Choose your starting location", countdown ring 40 px, "Deploying in 5…", title 14 px |
| Top status pill | UI/TopStatus.luau (509) | top centre, `top = 12 + inset` (:182-186) | match clock + limit, phase, WORLD CONTROL bar with gold 80% goal line for you and leader; phones: mini pill top-right |
| Command bar | UI/CommandBar.luau (965) | bottom centre, 12 px above bottom (:348-349); tray 8 px above it | nation chip, troops (cap, growth, fill), attack-ratio stops, gold + income, 10 build/nuke slots (keys 1-0), gold SHOP slot 58 px (:47); flows WIDE / STACKED / COMPACT |
| Build slot | UI/BuildButton.luau (486) | in command bar | icon, cost, hotkey badge, owned count, disabled state still clickable to explain; locked arsenal kind shows gold lock |
| Attack ratio | UI/RatioSlider.luau (254) | in command bar | 5 stops 10/25/35/50/75 %, default 25 % (UICtx.luau:52-55); wheel/Q/E step |
| Leaderboard | UI/Leaderboard.luau (663) | top-right, width 300 (250 compact), 12 px margin, drops under status pill if overlapping (UIRoot.luau:2222-2240) | top 10 by land share: colour, name, land %, troops; own row pinned; allies/traitors marked; click focuses camera; starts closed each match; Tab toggles |
| Attacks panel | UI/AttacksPanel.luau (462) | right, under leaderboard, down to command bar - 8 | incoming fronts red + Focus; outgoing with troops + Retreat; 6 rows desktop, 2 phone |
| Event feed | UI/EventFeed.luau (616) | lower-left, bottom = bar top - 12 | toasts coloured by category; 6.5 s (info 4, alert 9); alliance request cards Accept/Decline with expiry bar; renewal Renew/Ignore |
| Notices | UIRoot notices (EventFeed top mode) | top, y = inset + 96 (70 compact) | UIRoot.luau:2256-2258 |
| Nuke alert | UI/AlertBanner.luau (260) | under status pill (+10) | red pulsing "INCOMING NUKE", turns green "INTERCEPTED!"; RED_TITLE #ff8c94, tint rgba(.26,.03,.07,.9) |
| War banner | UI/Banner.luau (188) | centre | "THE WAR BEGINS" letter-spaced title on soft band, fade in/hold/out |
| Tooltip | UI/Tooltip.luau (314) | follows cursor / anchored above control / pinned corner | spec {title, swatch, badge, sub, rows k/v, body, hint, footer}; pin 6 s |
| Float text | UI/FloatText.luau (90) | near cursor, drifts up | "Attacking Brazil with 24.5K", "Not enough gold" |
| Radial menu | UI/RadialMenu.luau (756) | right-click / long-press | annular segments from UiShapes masks (ri 44 / ro 116 desktop, hover ro 122), sub-rings Build ▸ / Nuke ▸, centre back/close, greyed items explain in caption |
| Target card | UI/TargetCard.luau (445) | touch | first tap selects, big "Attack · 12.3K", Ally, Donate, Break alliance with Traitor warning |
| Unit card | UI/UnitCard.luau (305) | selected warship | hp bar, veterancy chevrons, state Patrolling/Returning/Repairing |
| Place confirm | UI/PlaceConfirm.luau (221) | touch, beside ghost | ✕ / ✓ |
| Coach marks | UI/Coach.luau (477) | tip + pulsing arrow | once per player |
| Tutorial | UI/Tutorial.luau (652) + Data/Tutorial.luau | top card "2 / 6" | steps with progress bar, tap marks |
| Help | UI/HelpOverlay.luau (712) | modal, scrolls | sections spawn, expand & attack, boats, economy, nukes, alliances, victory + controls (62 strings) |
| Game menu / Settings | UI/PauseMenu.luau (839) | modal, two pages | resume, how to play, settings, leave/surrender with confirm; SETTINGS: music, border pop, territory labels, select-before-attack, show tips again, music level slider |
| Game over | UI/GameOver.luau (1171) | modal | victory/defeat/eliminated/time-up, winner, stats (peak share, max troops, kills, duration), play again / spectate / title, Stars payout |
| Busy chip | UI/BusyChip.luau (118) | centre pill | "Deploying a new world…" spinner |
| Spectate pill | UIRoot | bottom centre, 14 px up | |
| Monetisation (not relevant to port) | Arsenal, ArsenalButton, ArsenalDemo, ShopSlot, Locker, CrateButton, CrateOpening, ChestView, FlagShop, ShopButton, ShopLayout, StarterButton, StarterOffer, GeneralButton, GeneralOffer, Takeover, Prices | | Robux/Stars shop screens |
| Platform glue | UILayoutProbe, TouchRouter, RotateCard, GlobeNotice, HoldRing, Telemetry, PartyPanel | | Roblox top bar/chat avoidance, touch, analytics, party |

The top-bar buttons (Main.luau header) are Music (M), Help, Leaderboard, Home (focus your nation, key Home) and Game menu, using the `hud_*` icons.

## Map rendering (src/client/Map)

- MapSurface draws one pixel per tile with nearest-neighbour upscaling.
  - Terrain colours: ocean #4785b5, shore sand #cccb9e, plains #bedc8a, highland #dccb9e, mountain #e6e6e6, background #3c3c3c (:193-198).
  - Territory alpha is 150/255 and saturation 0.85.
  - Factors: border darken 0.125, highlight brighten 0.25, friendly tint 0.35, defense checker 0.7 / fill 0.85 (:50-56).
- NameLayer places each name in the largest inscribed rectangle of the owner's main cluster on a coarse grid. Font size is `min(w/len*2, h/3)`, recomputed every 30 ticks.
- FrontLayer shows a troop label per front every 200 ms.
  - Outgoing labels are blue #3fa9f5 and incoming ones red #f87171.
  - It keeps the 2 largest 8-connected clusters and drops clusters under 30 tiles.
- FxLayer draws the nuke shockwave ring to 1.5x the blast radius over 1.5 s, with a white flash. Destroyed ships and shot-down nukes get a 0.8 s ring. Conquest shows a victory flag (MapFx atlas, 10 frames 24x24 at 90 ms, 22 tiles wide, 2.5 s) and a gold popup.
- FalloutGlow: fresh fallout heat decays over 25.5 s.
- StructureLayer plate shapes:
  - city squircle, port disc, factory cog, defense shield
  - SAM dome, silo bullet, artillery diamond, airfield runway, railgun hexagon
  - Fill is the owner colour at value x0.65 and the rim is the border colour at x0.1. Plates under construction are grey 198/127.
- UnitLayer uses 13x13 sprites drawn 13 tiles wide. Light pixels take the territory colour and dark pixels the border colour.
- RoadLayer draws a 1-tile line when zoomed out and a 3x3-per-tile track when zoomed in.
- RangeLayer draws SAM/defense/warship rings.
- WakeRoute smooths boat paths.

## Number formatting

- Troops (NumberFormat.luau:12-38) are floored, never rounded: 1234 → 1.23K, 24567 → 24.5K, 123456 → 123K, 1259999 → 1.25M, ≥1e10 → x.xB. Upstream stops at B and shows troops as internal / 10.
- Gold and other numbers use fmt_num (UITheme.luau:1890-1911), which rounds printf-style.
- fmt_cost gives 50K / 1.5M, fmt_pct gives `%.1f%%` (or `%.2f%%` under 1 %), fmt_time gives `m:ss` / `h:mm:ss`, and fmt_rate gives `+1.5K/s` or `±0/s` (:1918-1953).
- Our live K/M/B/T/Qd/Qt formatter and smooth +/s rates stay as they are. The ui_upstream/number_format.gd port is for reference and is tested.

## Icons and textures

- `UITheme.icon(name)` resolves in this order: builtin robux, then crate, then MapSprites.ui, then UiIcons, then ArsenalArt.ui (UITheme.luau:1355-1415). Masks are 128 px white and tinted at draw time.
- All 59 keys map to existing res:// PNGs in this project (icons.json `godot`). None are missing. Keys used dynamically or with no PNG: `calm`, `crate`, `robux`.
- The atlas cell layouts and orders are in atlases.json:
  - glyphs 64 px, 9 columns: city, port, factory, defense, sam, silo, artillery, airfield, railgun
  - plates 112 px, 2 rows (rim and fill)
  - units 13 px, 12 columns: transport, trade, warship, atom, hydrogen, mirv, sam, shell, warhead, train, carriage, carriage_loaded
  - status 256 px, 3 columns, pad 16: crown, traitor, disconnected, alliance, allianceRequest, target, embargo, nukeRed, nukeWhite, allianceFaded, doomsdayClock, verified
- docs/TEXTURES.md already covers byte-identical provenance of the 105 PNGs.

## Sounds (audio.json)

- Logical ids map to files in UICtx.SFX (UICtx.luau:58-102). Examples: click → ui_click, deny → ui_error, boat → boat_launch, explosion → nuke_explosion, alarm → nuke_alarm, eliminate → eliminate (BedWars kill sound, which replaced the old "conquer" sting).
- Event routing (UIAdvisor.luau) matches your "only my own events" rule:
  - build: only when I gain or lose the structure (UIRules.on_structure, UIRules.luau:339)
  - boat/warship: only my own units (UIRules.luau:364)
  - nuke_launch: only my own nukes, not warheads
  - nuke_alarm: nukes aimed at my land
  - explosion: 0 dB when it's mine or hits my land, otherwise -3 dB and only when on screen
  - attack launch/receive: no sound at all since 2026-09-27; it was "more annoying than useful" (:608-610)
  - naval news: silent
  - other ALERT messages: ui_tab at -4 dB
  - border growth: expand_pop "bubble pop" runs, 2/s at 40 tiles/s rising to 20/s at 600, pitch 0.8→1.1 over 15 s, -9..-3 dB
- The `conquer` sound exists in the manifest, but no client code in this commit triggers it.
- Mixing: 18 voices. Per-sound throttle, max-same, priority and cooldowns with fallback accents (e.g. boat_launch at most every 1.5 s, otherwise order_ack). Big sounds auto-duck the music (nuke_explosion -8 dB for 2.5 s, victory -14 dB). Music is at -6 dB with a 2 s crossfade (AudioDirector.luau:114-390).
- Music is 33 Rodrigo Flores tracks (CC BY 4.0) in 6 moods: title, wait, calm, war, victory and defeat. War holds for 40 s after the last fight, and tribes don't count (MusicMood.luau).
- There are no audio files in the repo. Every sound and track is a Roblox asset id, so only names, lengths and rules can be extracted.

## Strings, catalog, hotkeys

- catalog.json lists the titles (Defense Post, SAM Launcher, Missile Silo, Hydrogen Bomb, …), short names (H-Bomb, SAM, …) and blurbs with `{placeholders}` filled from Rules (UIRules.luau:48-130). It also has the placement reasons ("Ports must be on your coast", …; UIRules.luau:768-775).
- Hotkeys (UIInteract.luau:1640-1690):

| key | action |
| --- | --- |
| 1-0 | city, port, factory, defense, sam, silo, warship, atom, hydrogen, mirv |
| Esc / X | cancel |
| H | help |
| Tab | leaderboard |
| Space | primary action at hover |
| Backspace | retreat latest |
| Q / E (or Shift+wheel) | attack ratio |
| M | music |
| Home | focus your nation |

  Our port's I (ICBM) is custom and has no upstream equivalent.
- Per-screen strings, with line numbers, are in strings_by_screen.json. The largest sets are UIRules 103, TitleScreen 79, GameOver 70, HelpOverlay 62, UIInteract 60 and UIRoot 53.

## Not extractable

- Audio: no files in the repo, only Roblox ids.
- Rubik font: Roblox font id only.
- UIKit shadows, the BusyChip spinner and the map thumbnails: Roblox asset ids only. The UiShapes images are in the repo as PNGs (assets/ui_shapes/: radial_page_0-4, title_vignette, title_glow, over_dim, arrow_head, disc_glow) but are not copied into this project.
- Flags are SVG only (assets/flags/*.svg, 258 files). They are not rasterised here.
- Globe textures and meshes (assets/globe, .glb + 38 PNG) are for the old 3D globe and not used by the 2D port.

## Appendix: module index (auto, from module_headers.json)

- `src/client/Main.luau` (645 lines): Port of scripts/main.gd: the client root. Creates the AudioDirector, the globe (WorldView) and the interface (UIRoot), wires them to the Session, and owns the top-bar buttons that the original put in Airship's HUD bar: Music toggle (also key M), Help, Leaderbo
- `src/client/Session.luau` (1775 lines): Port of scripts/net/session.gd (client half): match orchestration for the title attract mode, solo campaigns and the shared multiplayer match. Same public API and signals as session.gd. 
- `src/client/init.client.luau` (19 lines): Airfront client entry. Owned by the Session/Main agent (see PORT.md §Ownership). Dev harness hook: if workspace attribute AF_DEV is set (in a developer's own Studio place), run src/client/Dev/<AF_DEV>.luau instead of the game. Never set AF_DEV in the shipped p
- `src/client/UI/AlertBanner.luau` (260 lines): Port of scripts/ui/alert_banner.gd (UIAlertBanner) Red pulsing "INCOMING NUKE" banner shown while nukes aimed at your land are in flight; turns green ("INTERCEPTED!") for a moment when a SAM shoots the last one down.
- `src/client/UI/Arsenal.luau` (1368 lines): The Arsenal (2026-10-04: units like Artillery and special nukes, unlocked by grinding Stars or with Robux): a modal for the items of Data/Arsenal. It opens from the title (ArsenalButton), from the command bar's SHOP button, and on its item when a locked unit i
- `src/client/UI/ArsenalButton.luau` (304 lines): The title screen's Arsenal button, left of the crate button (its twin, CrateButton.luau): the Arsenal's shield on a gold glow and slow rays, an ARSENAL pill under it, and a badge with the player's Stars (Data/Stars: what every match pays, spent in the Arsenal)
- `src/client/UI/ArsenalDemo.luau` (1462 lines): The Arsenal's gameplay previews: each card's art plays a few seconds of what its item does in a match, over and over (2026-10-12: the shop shows gameplay, as too few players were using it). The scene is drawn like the
- `src/client/UI/AttacksPanel.luau` (462 lines): Port of scripts/ui/attacks_panel.gd (UIAttacksPanel) Active attacks involving you (right side, under the leaderboard): incoming fronts in red with a Focus button, outgoing fronts and expansions with their committed troops and a Retreat button.
- `src/client/UI/Banner.luau` (188 lines): Port of scripts/ui/banner.gd (UIBanner) Centre-screen moment ("THE WAR BEGINS"): a wide letter-spaced title over a soft band that fades in, holds and fades out, then frees itself.
- `src/client/UI/BorderTracker.luau` (327 lines): Port of scripts/ui/border_tracker.gd (class UIBorders) Incrementally tracks the local player's border tiles so the UI can answer "do I border this owner?" and "can a boat reach that coast?" instantly (the Sim still validates everything).
- `src/client/UI/BuildButton.luau` (486 lines): Port of scripts/ui/build_button.gd (UIBuildButton) One build / nuke slot of the command bar: icon, cost, hotkey badge, owned count and a clear disabled state. Stays clickable when unavailable so a click can explain why.
- `src/client/UI/BusyChip.luau` (118 lines): Port of scripts/ui/busy_chip.gd (UIBusyChip) Small centred "Deploying a new world…" pill with a spinner, shown while Session builds a match.
- `src/client/UI/ChestView.luau` (117 lines): The cosmetic crate's 3D chest in a ViewportFrame (Assets/CrateModel: BedWars' voxel block chest), shared by the opening show (CrateOpening), the title screen's crate button (CrateButton) and the Locker's crate card. build() makes the camera and the parts; pose
- `src/client/UI/Coach.luau` (477 lines): Port of scripts/ui/coach.gd (UICoach) First-match coach marks: one short tip at a time with a pulsing arrow to what it talks about (a spot on the globe or a HUD control). Each tip shows once per player; "seen" ids persist in
- `src/client/UI/CommandBar.luau` (965 lines): Port of scripts/ui/command_bar.gd (UICommandBar) Bottom command bar: nation chip, troops (with cap, growth and fill), the attack-ratio slider, gold (with income, next to the slots it buys) and the ten build / nuke slots. Re-flows between a single
- `src/client/UI/CountLabel.luau` (68 lines): Port of scripts/ui/count_label.gd (UICount) Label that animates between numeric values (troops, gold, percentages). Fixed-width tabular rendering (UITheme.fix_width) keeps the rolling digits from jittering.
- `src/client/UI/CrateButton.luau` (381 lines): The title screen's crate button, top right (2026-09-29: on phones the chest button was hard to notice, so it got more to catch the eye). The 3D chest (ChestView) wiggles on a glow and slow rays with a twinkle or two, a CRATES pill under it, and a badge:
- `src/client/UI/CrateOpening.luau` (1520 lines): Opening a cosmetic crate: a Clash Royale-style show around a 3D chest (2026-09-29: the first version of opening a crate was not satisfying at all, and it should be super fun; the show was then made 3D, around a ready-made voxel chest).
- `src/client/UI/EventFeed.luau` (616 lines): Port of scripts/ui/event_feed.gd (UIEventFeed) Lower-left event feed: stacking toasts coloured by message category that fade on their own, plus actionable alliance cards with an expiry bar: requests (Accept / Decline) and the
- `src/client/UI/FillBar.luau` (208 lines): Port of scripts/ui/fill_bar.gd (UIBar) Rounded progress track with an animated fill, optional goal line and value markers.
- `src/client/UI/FlagShop.luau` (867 lines): The flag shop (2026-10-22: a daily rotating shop of flags for sale; Data/Shop, docs/flag-shop.md): a modal from the title's shop button. A running limited set first (Halloween: the whole set, ENDS IN its clock), then today's flags (Data/Shop.daily, NEW IN the 
- `src/client/UI/FloatText.luau` (90 lines): Port of scripts/ui/float_text.gd (UIFloatText) Brief confirmation pill that pops near the cursor, drifts up and fades ("Attacking Brazil with 24.5K", "Not enough gold"...).
- `src/client/UI/GameOver.luau` (1171 lines): Port of scripts/ui/game_over.gd (UIGameOver) Victory / defeat / eliminated / time-up screen with the winner, your match stats and the next steps (play again, spectate, return to title).
- `src/client/UI/GeneralButton.luau` (354 lines): The title screen's RoWorld General button (Data/Subscription; 2026-10-27), under the flag shop's and the starter pack's: a night-blue card edged in gold, a general's three stars on a slowly turning sunburst, GENERAL in gold, a line that cycles through what a G
- `src/client/UI/GeneralOffer.luau` (444 lines): RoWorld General's window (Data/Subscription; 2026-10-27): what the monthly subscription gives, and SUBSCRIBE, which opens Roblox's own prompt (MarketplaceService:PromptSubscriptionPurchase). Roblox bills and renews it; the server hears of it (server/General, O
- `src/client/UI/GlassPanel.luau` (216 lines): Port of scripts/ui/glass_panel.gd (UIGlass) Frosted-glass panel: navy tint, 1 px light border, a top sheen line and a soft drop shadow. Lays out its children like a PanelContainer (inside the padding).
- `src/client/UI/GlobeNotice.luau` (251 lines): Territory-map notice (review_code.md R2-3). The globe draws territory colours with Editable images / meshes; when the device's editable budget is exhausted, or the experience's Mesh / Image APIs permission is off in a published place, it falls back to the stat
- `src/client/UI/HelpOverlay.luau` (712 lines): Port of scripts/ui/help_overlay.gd (UIHelpOverlay) "How to play" overlay: illustrated sections (spawn, expand & attack, boats, economy, nukes, alliances, victory) and the mouse/keyboard and touch controls. Scrolls on small screens.
- `src/client/UI/HoldRing.luau` (71 lines): Touch: a ring that closes in around a finger held on the map until the long-press menu opens (2026-09-29: the press-and-hold quick build menu felt inconsistent on phones). It shows that the hold is counting (keep still) and when it will open. Driven each frame
- `src/client/UI/Leaderboard.luau` (663 lines): Port of scripts/ui/leaderboard.gd (UILeaderboard) Right-side leaderboard: top 10 by land share with colour, name, land % and troops. Your own row is pinned when you are outside the top 10; allies and traitors are marked. Clicking a row focuses
- `src/client/UI/Locker.luau` (964 lines): The Locker (2026-09-29: cosmetic loot boxes of territory skins and flags to unlock): a modal from the title with the crate card on the left and what you own on the right.   crate card  the crate art, "a territory skin or a flag you don't own yet", the player's
- `src/client/UI/MapPicker.luau` (340 lines): Map picker (the single-player map list): a modal grid of map cards (thumbnail, name, size) under category tabs. The footer names the public-domain data the World map is made from. The grid is a Roblox ScrollingFrame with a UIGridLayout hosted in a kit Control 
- `src/client/UI/PartyPanel.luau` (471 lines): The party on the title screen (server/Party; team games on: Rofront Staging only for now). Who is in it (the leader picks the public match and everyone goes with them; a team game puts them on one team), the invites to answer, and an invite list: the players o
- `src/client/UI/PauseMenu.luau` (839 lines): Port of scripts/ui/pause_menu.gd (UIPauseMenu) Game menu: resume, how to play, settings, and leave / surrender with a confirmation step. 
- `src/client/UI/PlaceConfirm.luau` (221 lines): Port of scripts/ui/place_confirm.gd (UIPlaceConfirm) Touch placement / launch confirmation: a small caption and two big buttons (✕ cancel, ✓ build or launch) floating next to the ghost on the globe, never over it. The buttons follow the
- `src/client/UI/Prices.luau` (117 lines): The Robux prices the interface shows: Roblox's own for this player (MarketplaceService), never the number in Data/Products once Roblox has answered. With Managed Pricing (dynamic pricing, on since 2026-10-05) a product's price differs by region and while Roblo
- `src/client/UI/RadialMenu.luau` (756 lines): Port of scripts/ui/radial_menu.gd Circular context menu (right-click / long-press). Segments carry an icon and a short label; unavailable actions are greyed and explain themselves in the caption under the ring. Items with
- `src/client/UI/RatioSlider.luau` (254 lines): The Attack bar: the share of the army an order sends, bound to UICtx.ratio. Five stops in one row (UICtx.RATIO_STOPS: 10% 25% 35% 50% 75%), each one a labelled target: tap a stop, or drag across them, and the amber thumb moves to it. The mouse wheel steps one 
- `src/client/UI/RotateCard.luau` (65 lines): Port of scripts/ui/rotate_card.gd (UIRotateCard) Full-screen "Rotate your phone" card shown on touch devices while the viewport is portrait (the game is designed for landscape; StarterGui.ScreenOrientation normally keeps us there).
- `src/client/UI/ShopButton.luau` (268 lines): The title screen's flag shop button (Data/Shop; 2026-10-22: a daily rotating shop of flags for sale), under the Arsenal and crate buttons: a purple card with the shop's flags taking turns on its left, FLAG SHOP, the running set's name (HALLOWEEN FLAGS) or NEW 
- `src/client/UI/ShopLayout.luau` (59 lines): The flag shop's layout (UI/FlagShop), apart so tests can run it without Roblox: the order of a section's cards and where each goes, with a section's Legendary on a FEATURED card 2 x 2 cells big (2026-10-24).
- `src/client/UI/ShopSlot.luau` (356 lines): The SHOP button that closes the build row (CommandBar): one gold button, a little wider than a build slot, that opens the Arsenal (2026-10-12: one button instead of six sub-buttons, as too few players were opening the shop and more of them should click it; fro
- `src/client/UI/SpawnOverlay.luau` (320 lines): Port of scripts/ui/spawn_overlay.gd (UISpawnOverlay) Spawn-phase banner: "Choose your starting location", a countdown ring, the solo "Deploying in 5…" count and, in multiplayer, how many commanders have placed their capitals.
- `src/client/UI/StarterButton.luau` (340 lines): The title screen's starter pack button, under the Arsenal and crate buttons, while the starter pack's offer runs (Data/Starter; 2026-10-15: available for a limited time only): a red card with the Mega Nuke's render, STARTER PACK, the regular price struck throu
- `src/client/UI/StarterOffer.luau` (776 lines): The starter pack's offer (Data/Starter; 2026-10-15: the starter pack at 39 Robux, on sale for a limited time only). A window over the title: LIMITED-TIME OFFER, STARTER PACK, the three items it unlocks (their shop renders on a glow of their colour, name and on
- `src/client/UI/Takeover.luau` (285 lines): Solo: take over the nation that eliminated you, for 25 Robux (2026-09-28). Offered on the ELIMINATED screen and the spectating pill while the nation that conquered you is still alive. A press pauses the match, then spends a saved credit or opens Roblox's purch
- `src/client/UI/TargetCard.luau` (445 lines): Port of scripts/ui/target_card.gd (UITargetCard) Touch "look before you act" card: the first tap on a foreign nation (or a coast reached by boat) selects it and shows who it is, with a big primary order button ("Attack · 12.3K"). A second
- `src/client/UI/Telemetry.luau` (524 lines): Match milestones for the Creator Dashboard (src/server/Analytics.luau logs them with Roblox's AnalyticsService). Solo matches run on this client, so the client reports for every match it plays: started (mode, map), spawned, first attack, whole minutes alive, e
- `src/client/UI/TitleScreen.luau` (1703 lines): Port of scripts/ui/title_screen.gd (UITitleScreen) Title screen over the live attract-mode globe: AIRFRONT wordmark, Play Solo with difficulty chips, Multiplayer with live server status, How to Play, credits. Also shows the "joining
- `src/client/UI/Tooltip.luau` (314 lines): Port of scripts/ui/tooltip.gd (UITooltip) Small glass info card. Three placements: following the cursor (tile hover), anchored above a control (button hints) or pinned in a corner (tap-to-inspect on touch screens).
- `src/client/UI/TopStatus.luau` (509 lines): Port of scripts/ui/top_status.gd (UITopStatus) Top-centre status pill: match clock (and time limit), phase, and world-control progress towards the 80 % victory share for you and the current leader. Phones get a one-line mini pill
- `src/client/UI/TouchRouter.luau` (120 lines): Port of scripts/ui/touch_router.gd (UITouchRouter) Multi-touch for the HUD. In Godot only the first finger drove the (mouse-based) ratio slider, so this node routed any other finger that lands on the slider to it. Roblox GUI objects receive
- `src/client/UI/TrayFit.luau` (63 lines): Widths in the build row (CommandBar): its slots, and the gold SHOP button that closes it (ShopSlot), a little wider than a slot while there is anything left to get. The row must stay one row wherever it can (2026-10-04: the build menu was too big; only the SHO
- `src/client/UI/Tutorial.luau` (652 lines): A new player's first match, step by step (Data/Tutorial: the steps and why; 2026-10-04: a new tutorial for new players, made for phones first). One small goal at a time:   * a card at the top of the screen: "2 / 6", one short line, a bar for a goal with progre
- `src/client/UI/UIAdvisor.luau` (917 lines): Port of scripts/ui/ui_advisor.gd Reactions to the match for the HUD: sounds and toasts for game events that involve you, threat warnings (a neighbour massing 5x your army, being attacked), first-match coach-mark triggers and
- `src/client/UI/UICtx.luau` (1490 lines): Port of scripts/ui/ui_ctx.gd Shared context for every UI component: duck-typed handles to Session / WorldView / AudioDirector (so lightweight stand-ins work in tests), the bound GameState, layout metrics, the attack ratio,
- `src/client/UI/UIInteract.luau` (1745 lines): Port of scripts/ui/ui_interact.gd Globe interaction for the HUD: hover tooltips and previews, primary clicks (spawn / expand / attack / boat / inspect), build & nuke placement mode, the radial context menu and its actions,
- `src/client/UI/UIKern.luau` (11 lines): GENERATED by tools/uikit/make_kern.py from Rubik's GPOS 'kern' pairs. Do not edit. Pair kerning in em/1000 per weight for letter-spaced (per-glyph) text: 6-char records "<first><second><signed value>", e.g. "LT-102" (printable ASCII, /kern/ >= 8).
- `src/client/UI/UILayoutProbe.luau` (215 lines): Port of scripts/ui/ui_layout_probe.gd (UILayoutProbe) Layout helpers for UIRoot: measures the platform's own HUD (the Roblox top bar row with Main's top-bar buttons, the chat window) so our panels stay clear of it, reads the device safe area,
- `src/client/UI/UIMaps.luau` (102 lines): The playable maps for the UI: the replicated registry (Data/MapList) joined with the uploaded thumbnails (Assets/MapThumbs, keyed by the source map folder name). Falls back to the one built-in map when the registry is missing.
- `src/client/UI/UIRoot.luau` (2542 lines): Port of scripts/ui/ui_root.gd (UIRoot) AIRFRONT interface root. Built entirely in code: title screen, spawn banner, HUD (command bar, world-control status, leaderboard, event feed, nuke alert), tooltips, radial menu, help, game
- `src/client/UI/UIRules.luau` (1383 lines): Port of scripts/ui/ui_rules.gd Client-side game knowledge for the interface: build/nuke catalogue, costs (via Rules), what a click on a tile would do, radial-menu contents and placement checks. These are hints only; the
- `src/client/UI/UITheme.luau` (1955 lines): Port of scripts/ui/ui_theme.gd AIRFRONT design system: colour tokens, the 8 px spacing scale, Rubik weights, text metrics, the icon cache, style factories and widget helpers. Everything is static so any component can use it.
- `src/client/UI/UnitCard.luau` (305 lines): Port of scripts/ui/unit_card.gd (UIUnitCard) Selected-warship card (compact on phones): health bar, veterancy chevrons with kills toward the next rank, state (Patrolling / Returning to port for repairs / Repairing) and, for your own
- `src/client/UI/Widgets.luau` (3151 lines): Port of scripts/ui/widgets.gd (UIWidgets animation helpers) plus the kit's Control engine.  The original UI is built from Godot Controls and Containers. Roblox auto-layout cannot express
- `src/client/Audio/AudioDirector.luau` (1330 lines): Port of scripts/audio/audio_director.gd: music + sound-effect director (client only).  - The soundtrack (Assets/Soundtrack.luau: Rodrigo Flores' Orchestral Ambients, 2026-09-27) plays by
- `src/client/Audio/MusicMood.luau` (75 lines): Which soundtrack mood fits the moment (AudioDirector.set_music_mood). Pure logic, polled by UIRoot:   title    the title screen                     wait     a public match's waiting room   calm     a match, no fighting                 war      fighting a natio
- `src/client/Audio/Playlist.luau` (90 lines): The soundtrack's playlists (Assets/Soundtrack.luau): which track plays next in a mood. Pure logic (no Roblox services), used by AudioDirector. 
- `src/client/Map/AtlasReady.luau` (46 lines): Tells a map layer when an image it would like to switch to can be drawn.  A layer that swaps two stacked images for one combined atlas (Sprites.units_one, Sprites.shapes_one) must not
- `src/client/Map/FalloutGlow.luau` (713 lines): The glow of fresh fallout on the 2D map (2026-10-12, so irradiated land looks better and glows: the fallout used to be a flat green, with no glow). How it is made:
- `src/client/Map/FrameClock.luau` (21 lines): The client's frame time: the real one (os.clock, RenderStepped's dt), except while a Studio film (Dev/Film: the trailer, 2026-10-12) steps time itself, a frame at a time, so a capture of each frame plays back smoothly. The session, the map and the HUD
- `src/client/Map/FrontLayer.luau` (411 lines): Troop counts on the local player's fronts (a label per attack front, floating over the map): every 200 ms, for each attack by the local player on another owner (blue #3fa9f5) and each attack on the local player by a player or nation, not a tribe (red #f87171),
- `src/client/Map/FxLayer.luau` (1015 lines): Effects on the 2D map: a nuke's shockwave ring grows to 1.5 x its blast radius over 1.5 s behind a white flash, a destroyed ship / shot-down nuke pops a small ring (0.8 s), and the camera shakes a little for nukes near the view. Pooled GUI circles.
- `src/client/Map/MapCamera.luau` (554 lines): 2D map camera for a flat tile map drawn in the GUI.  Map space: u = tile column + fraction (0..W), v = tile row + fraction (0 = top edge .. H); a
- `src/client/Map/MapInput.luau` (731 lines): Map input (from scripts/view/globe_input.gd): mouse, trackpad and multi-touch for MapView, driving the MapCamera through its camera-rig API (drag pans the map, wheel / pinch zoom about the pointer). "Globe" below means the map.
- `src/client/Map/MapSurface.luau` (1517 lines): The 2D map surface (terrain, territory and borders): one pixel per tile, nearest-neighbour upscaled (ResampleMode Pixelated) so tiles stay crisp squares at any zoom. 
- `src/client/Map/MapView.luau` (985 lines): The 2D world view (a flat tile map), replacing the 3D globe WorldView with the same public API (DESIGN.md §10), so UIRoot / Main / Session drive it unchanged:   signals tile_hovered(tile), tile_clicked(tile), tile_context(tile, screen_pos),
- `src/client/Map/NameLayer.luau` (762 lines): Owner names + troop counts on the 2D map:   * placement (_place): the bounding box of the owner's main     cluster, a grid at a coarse scaling factor (1..32 by the box size) where a cell is usable if
- `src/client/Map/RangeLayer.luau` (717 lines): Range rings on the 2D map: SAM interception coverage and defense-post protection radius, the prospective ring while placing one, and the selected warship's patrol / targeting rings. The choice of rings is the globe RangeLayer's (View/RangeLayer.luau _rebuild),
- `src/client/Map/RoadLayer.luau` (672 lines): Railroads on the 2D map: every railroad follows its tile path (GameState.roads: rid -> {a, b, tiles}) and fades in over FADE_RANGE up to zoom MIN_ZOOM. Zoomed out it is a line a full-size tile wide along the path's centre (THICKNESS 1: the path's straight
- `src/client/Map/StructureLayer.luau` (633 lines): Structure icons on the 2D map:   * a plate per structure in its kind's shape (Assets/MapSprites: City squircle, Port disc, Factory     cog, Defense Post shield, SAM Launcher dome, Missile Silo bullet, Artillery diamond, Airfield
- `src/client/Map/TrailBudget.luau` (34 lines): How much of the munitions in flight UnitLayer draws: every trail dot and every target ring is a GUI object, so their number has a ceiling whatever the Sim has in the air. 
- `src/client/Map/UnitLayer.luau` (742 lines): Units on the 2D map:   * sprites from the unit atlas (13 x 13 px, drawn 13 full-size tiles wide, so they     scale with the map), recoloured: light pixels in the owner's territory
- `src/client/Map/ViewRules.luau` (145 lines): Port of scripts/view/view_rules.gd — gameplay numbers the view draws (SAM / defense ranges, nuke radii, interception odds), read from Rules at runtime so range rings and aim previews follow the Sim when it is retuned. Prefers Rules' functions and falls back to
- `src/client/Map/WakeRoute.luau` (211 lines): A transport ship's route as a smooth line (UnitLayer draws the ship and its wake along it).  The Sim's water paths are string-pulled (SimNav._smooth): long straight legs that meet at sharp
