# Frontline Conquest (v7)

A real-time territory-conquest strategy prototype built in **Godot 4.3 (GDScript)**.

Current behavior, audio, and art are documented in `docs/MECHANICS.md`, `docs/AUDIO.md`, and `docs/TEXTURES.md`. Music is only `sounds/music/frontline_bed.wav` (a looping original bed). The older theme mp3s are in `sounds/rejected/` and are not played. Effects play from `sounds/play/` (PCM copies of the OpenFront files). Structure and HUD art is the fork's PNG set (AGPL-3.0), byte-checked in `docs/TEXTURES.md`. Sound effects are OpenFront CC BY-SA 4.0 files from commit `030274df` (`sounds/LICENSE.txt`).

The feature list under this line is an older prototype note. Where it disagrees with `sim/` and `main.gd` (MIRV, ice, blast sizes), the code and `docs/MECHANICS.md` are the ones that run.

## Key Features (v1 – v7)

### 1. Economy, Rail Networks & Maritime Trade
- **Logistic Population Growth**: Follows OpenFront's `r^0.73 * (1 - r)` growth curve peaking at **~42.2% of max capacity** (marked with a gold tick on the troop bar).
- **Entity Cap Scaling**: Human `1.0x`, Protagonist AI Nations `0.5x / 0.75x / 1.0x` by difficulty, Passive Tribes `0.33x`.
- **Factories & Moving Gold Trains**: Factories automatically connect via railway tracks (with sleepers/ties) to nearby owned or allied Cities, Ports, and Factories, spawning moving **Trains** that award **10,000 gold** (own station) or **35,000 gold** (allied station), with distance fatigue after 9 stops (floored at 5,000).
- **Ports & Nonlinear Sea Trade**: Coastal Ports automatically spawn **Trade Ships** along cached water paths, paying both sender and receiver via OpenFront's nonlinear distance formula (`floor((75000 / (1 + exp(-0.03 * (d - 300))) + 50 * d) * mult)`) with a global sigmoid spawn cap.

### 2. In-Place Building Level Upgrades, Construction Timers & Price Ladders
- **In-Place Leveling (`Lv2`, `Lv3`, ...)**: Clicking an existing owned `City`, `Port`, `Factory`, `SAM Launcher`, `Missile Silo`, `Artillery`, or `Airfield` while its build tool is active upgrades its level in-place without needing 15-tile spacing.
  - **City**: `+25K` max troop cap per level (`125K -> 250K -> 500K -> 1M` cap).
  - **Port & Factory**: Share the same exponential price ladder (`125K -> 250K -> 500K -> 1M` cap); higher levels boost train/ship output.
  - **Defense Post**: `50K -> 100K -> 150K -> 200K -> 250K` cap; 30-tile radius (`5x` attacker troop loss, `3x` capture time, non-stacking).
  - **SAM Launcher**: `1.5M -> 3M` cap; range scales by `150 - 480 / (level + 5)` (70 tiles at Lv1, 81 at Lv2, 90 at Lv3, up to 150) and adds `+1` interception slot per level (`9s` reload per slot).
  - **Missile Silo**: Flat `1M`; `9s` reload cooldown and `+1` parallel launch tube per level.
  - **Warship**: `250K -> 500K -> 750K -> 1M` cap; 1,000 HP, 250 dmg/shell, sinks transports, captures enemy trade ships, gains veterancy.
  - **Artillery**: `150K` base; shells enemies within 45 tiles, halving firing interval per level (`2.0s / 2^(Lv-1)`), destroying enemy structures after 15 hits.
  - **Airfield (Air Strike)**: `400K` base; launches bomber sorties every 60s (`5` warheads base, `+1` warhead per upgrade level).
  - **Railgun**: `300K`; instant un-interceptable strike anywhere on the map.
  - **MIRV**: Disabled (`Not available in this prototype yet`) per design spec.
- **Construction Timers**: Newly placed and upgraded structures display a live circular construction progress ring on the map before activating.

### 3. 3-Tier Terrain, Border-Smoothing Combat & Fallout
- **3 Passable Terrain Tiers + Impassable Ice**:
  - **Plains** (pale green): `0.8x` troop loss, fastest capture.
  - **Highlands / Steppe** (warm tan): `1.0x` troop loss, `1.25x` capture time.
  - **Mountains** (grey/white peaks): `2.0x` troop loss, `2.5x` capture time.
  - **Ice Caps**: Unclaimable.
- **Smooth Frontlines**: Frontier expansion scores candidate tiles by `Plains > Highlands > Mountains` and strongly prioritizes tiles with multiple orthogonal neighbors already owned by the attacker.
- **Radioactive Fallout**: Nuke blasts leave decaying fallout that multiplies capture cost and delay by `5.0 - progress * 2.0` (`5x` tapering to `3x`).

### 4. Diplomacy, Alliances, Donations, Embargoes & Betrayal
- **Right-Click Diplomacy Menu**: Right-click any nation to open the interactive diplomacy panel:
  - **Propose / Break Alliance** (5-minute duration with 30s expiry renewal warning card).
  - **Donate 1/3 Troops** & **Donate 25% Gold** (10s cooldown).
  - **Embargo Trade (5:00)** & **Embargo All** toggle (halts trade ships and trains with embargoed nations; attacking automatically triggers a 5-minute embargo).
- **Traitor Penalty (`30s`)**: Breaking an alliance marks the nation `[TRAITOR]` (`0.5x` defense, `0.8x` attack speed, automatic embargo).

### 5. End-of-Match Screen, Stars & Arsenal
- **End-of-Match Screen**: Shows `MATCH COMPLETE`, `VICTORY` / `DEFEAT`, land percentage outside fallout, 4 stat cards, stars earned, and next Arsenal unlock progress.
- **Arsenal (4x2 Grid)**: Spend stars (saved in `user://save.json`) to unlock Mega Nuke, Scattershot, Reinforcements, Artillery, Air Strike, Railgun, 2x Stars, and Rapid Reload.

## How to Run
```bash
godot --path /workspace/frontline-godot
```
- **Automated Screenshot Suite**:
  ```bash
  xvfb-run -a -s "-screen 0 1600x900x24" godot --path /workspace/frontline-godot --resolution 1600x900 -- --autoshot
  ```
- **10x Speed Performance Benchmark**:
  ```bash
  godot --headless --path /workspace/frontline-godot -- --bench
  ```
