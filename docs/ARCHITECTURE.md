# Architecture

main.gd used to be one 9,300 line script. It is now a chain of scripts, each extending the previous one,
so the game is still a single class (every member and `m.some_func()` call in tests works unchanged).

```
state -> map -> nations -> economy -> nukes -> navy -> rails -> bot_ai -> draw_helpers -> planes_fx
      -> diplomacy -> ui_anim -> ui_build -> strikes -> end_screen -> shop -> audio -> main
```

| File | Contents | Upstream RoWorld counterpart |
|---|---|---|
| game/state.gd | constants, variables, inner classes, forward declarations | shared/Core/GameState, SimState, Defs |
| game/map.gd | map generation, tiles, ownership | shared/Core/WorldMap, MapCodec; client/Map/MapView |
| game/nations.gd | nations, spawn phase | Sim (_create_nations, _random_start) |
| game/economy.gd | economy, building, attacks, combat | Sim, SimAttacks, SimStructures |
| game/nukes.gd | nukes, MIRV, fallout, SAM | SimNukes, SimArsenal |
| game/navy.gd | boats, warships, trade ships | SimNaval, SimWarships |
| game/rails.gd | rails and gold trains | client/Map/RoadLayer |
| game/bot_ai.gd | protagonist AI hooks | SimAI, SimAIEconomy |
| game/draw_helpers.gd | sprites, icons, wakes, quality | client/Map/UnitLayer, WakeRoute |
| game/planes_fx.gd | cargo and transport planes, world effects, notes | client/Map/FxLayer |
| game/diplomacy.gd | alliances, embargoes | Sim (alliances), Teams |
| game/ui_anim.gd, ui_build.gd | menus, panels, HUD building, settings | client/UI/* |
| game/strikes.gd | air strike, railgun | SimArsenal |
| game/end_screen.gd | end-of-match screen | client/UI end screen |
| game/shop.gd | shop and arsenal | client/UI shop |
| game/audio.gd | sound and music | client/Audio/AudioDirector, Playlist |
| main.gd | game loop, overlay drawing, input, capture tools | client/Map/MapInput, MapCamera |

The numbers-only simulation lives under sim/ (rules, attacks, arsenal, naval, warships, nav, ai) and
mirrors upstream shared/Core. The upstream HUD port is under ui_upstream/.

## Forward declarations
GDScript rejects a call to a function that a later script in the chain defines. Any function called from an
earlier layer than the one defining it has a stub in game/state.gd; the real definition overrides it.
When you add a call upward in the chain, add a stub with the same signature there.

## Source-text tests
Tests that grep the game source read it through `tests/upstream/_harness.gd: game_src()`, which joins main.gd
and game/*.gd.
