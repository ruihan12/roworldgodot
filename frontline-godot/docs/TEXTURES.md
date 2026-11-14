# Textures taken from this fork

Source tree: `https://github.com/ruihan12/roworldgodot` commit `ae7a3505e6f3736aef85fffc1879c0476f819c59` (the `main` this branch was cut from). Every PNG under that tree, excluding `frontline-godot/` and `.git`, was hashed (sha256 of the file bytes) and compared to every PNG in this Godot project. The machine-readable list is `docs/texture_inventory.json`. Contact sheets: `docs/texture_contact_sheet.png` (structure and HUD icons) and `docs/texture_atlases.png` (plates, glyphs, units, map fx, rails).

The Godot code loads PNGs by reading the bytes at runtime (`_tex` in `main.gd`), not by recreating the drawings. `assets/LICENSE-AGPL-3.0-RoWorld.txt` is the upstream license. Upstream code license is AGPL-3.0 (`/LICENSE` at the repo root).

## Counts

| set | count |
| --- | --- |
| PNG files in the fork at that commit | 231 |
| Distinct hashes among those | 229 (two pairs share bytes) |
| PNG files in this Godot project | 106 |
| Byte-identical to a fork file | 105 |
| Only in the Godot project | 1 (`assets/ui/icbm.png`) |
| Fork PNGs with no copy in the Godot project | 125 |

`icbm.png` has no counterpart in the fork. ICBM is a port control (key `I`, whole-map range, +10% launch cost). The icon stays as the port drew it. The project icon is `assets/ui_icons/app_icon.png`, which matches `assets/ui_icons/app_icon.png` in the fork, set as `config/icon` in `project.godot`.

## Integrated (byte-identical)

These are the files the running game draws. Hashes are in the JSON. Intended use is the call site.

| Godot path | Used for |
| --- | --- |
| `assets/ui/*.png` except `icbm.png` | Build-bar and map icons (`UI_TEX` in `main.gd`) |
| `assets/arsenal/ui/*.png` | Mega, scatter, reinforce, and the arsenal grid |
| `assets/arsenal/renders/*.png` | Arsenal card renders |
| `assets/arsenal/fx/*.png` | Blast, smoke, reticle, warhead, and related frames |
| `assets/ui_icons/*.png` | HUD, target reticle, troops, gold, buttons |
| `assets/plates.png`, `assets/glyphs.png`, `assets/units.png` | Map structure plates and unit atlas (`_map_icon`, `_unit_sprite`) |
| `assets/map_fx/map_fx.png` | Effect atlas (`_rw_frame`) |
| `assets/rails/*.png` | Rail sprites shipped beside the vector rail drawing |
| `assets/status.png` | Status atlas |

No structure icon in that set was redrawn for this change. They already matched the fork byte for byte, so they were left as the originals.

## In the fork, not copied into the running game

Not missing from the fork. Left out on purpose.

**Globe** (`assets/globe/`, 32 PNGs: `base_*`, `col_*`, `dat_*`, `m_col_*`, `m_dat_*`, `cap_n`, `cap_s`, `moon`, `sky_*`). These are the 3D globe color, data, and sky faces. This port is a flat 1792×1600 map. The task keeps that map and does not add Antarctica or ice. Wiring the globe would be a different game.

**Shop flags** (`assets/shop_flags/art/`, 32 PNGs). Cosmetic flag art for the upstream shop. This port has no shop and no flag picker.

**Sprite masters** (`assets/map_sprites/src/glyph_sheet.png`, `status_sheet.png`, `unit_glyph_sheet.png`, plus `plates_one.png` and `units_one.png`). Source sheets. The atlases the game samples (`plates.png`, `glyphs.png`, `units.png`, `status.png`) are already the integrated copies.

**UI shape kit** (`assets/ui_shapes/`, 11 PNGs: discs, radial pages, title glow, vignette, arrow). The port's windows are `StyleBoxFlat` panels with corner radius (the rounded UI). Replacing those panels with the shape kit would change the layout. They stay in the fork only.

**Branding** (`assets/branding/experience_icon_512.png`). The 512 px experience icon. The in-game icon used above is the smaller `app_icon.png` from `assets/ui_icons/`, which is the same art the HUD already loads.

**Tool outputs** (`tools/fx/out/`, `tools/glyphs/out/`). Generator products. The packed atlases above are what the game samples. The loose frames are not a second copy of the same art in the running scene.

## Not in either tree

RoWorld image ids in `src/shared/Assets/*.luau` that are only `rbxassetid://…` and have no PNG next to them are not files in git. Examples: several arsenal renders are also checked in as PNG under `assets/arsenal/`, and those PNGs are the ones integrated. Ids with no PNG were not fetched from Roblox (the asset API returned 403 for the audio ids, and the same restriction applies to private images). Nothing here pretends a missing Roblox image was recreated.
