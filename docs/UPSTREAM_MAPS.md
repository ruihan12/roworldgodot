# Upstream RoWorld maps

Converter: `python3 tools/convert_upstream_maps.py [/workspace/roworld_src]`. It needs numpy, Pillow, zstandard and scipy, and its output is deterministic. Loader: `sim/upstream_maps.gd`. Test: `godot --headless --path . -s res://tests/test_upstream_maps.gd`.

## Decoding

The upstream codec (src/shared/Core/MapCodec.luau) stores `terrain = base64(zstd(W*H bytes))` with codec "zstd+base64". The tile byte format (src/shared/Core/WorldMap.luau:17-25) is:

- bit 7 land
- bit 6 shoreline
- bit 5 ocean
- bits 0-4 magnitude (land elevation 0-30; water `ceil(dist to coast / 2)`, cap 31)
- 0x9F impassable (ice cap)

The converter is a Python port of the codec. All 8 maps decode to exactly W*H bytes, and each decoded land count equals the module's `land_tiles` (World 689,018, Africa 963,230, Asia 1,202,586, Europe 831,821, North America 738,172, South America 587,124, Pangaea 308,767, Onion 159,270). None of the maps contains 0x9F.

## Maps found

| id | name | source size | crop | scale | placed (x,y w x h) | k_lin | land tiles | nations | resample |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| world | World | 2000x1000 | [0, 17, 2000, 1000] | 0.896 | 0,359 1792x881 | 1.116 | 553514 | 71 | nearest |
| africa | Africa | 1489x1332 | [0, 0, 1489, 1319] | 1.203 | 0,6 1792x1587 | 0.831 | 1394759 | 45 | nearest |
| asia | Asia | 1536x1350 | [0, 0, 1536, 1350] | 1.167 | 0,12 1792x1575 | 0.857 | 1636701 | 64 | nearest |
| europe | Europe | 1422x1254 | [0, 0, 1422, 1254] | 1.260 | 0,10 1792x1580 | 0.793 | 1320759 | 48 | nearest |
| northamerica | North America | 1655x1224 | [0, 0, 1655, 1224] | 1.083 | 0,137 1792x1325 | 0.923 | 865266 | 50 | nearest |
| southamerica | South America | 1165x1420 | [0, 0, 1083, 1406] | 1.138 | 280,0 1232x1600 | 0.879 | 760036 | 36 | nearest |
| pangaea | Pangaea (test fixture) | 1000x1000 | [0, 21, 1000, 794] | 1.792 | 0,107 1792x1385 | 0.558 | 991102 | 29 | nearest + edge smoothing |
| onion | Onion (test fixture) | 512x512 | [12, 4, 506, 498] | 3.239 | 96,0 1600x1600 | 0.309 | 1670962 | 3 | nearest + edge smoothing |

Sources:
- src/shared/Data/Maps/World.luau
- src/server/MapData/{Africa,Asia,Europe,NorthAmerica,SouthAmerica}.luau
- tests/fixtures/maps/{Pangaea,Onion}.luau
- The registry is src/shared/Data/MapList.luau.

Pangaea and Onion are upstream test fixtures, not part of the game's map list. To hide them, edit `ORDER` in sim/upstream_maps.gd.

## Scaling

1. Crop to the land bounding box plus 8 tiles.
2. Apply one uniform scale `min(1792/cw, 1600/ch)`, so aspect is kept.
3. Centre the result in a 1792x1600 ocean grid.
4. Sample with upstream's own `WorldMap._resample` rule, where each new tile takes the source tile under its centre (WorldMap.luau:224).
5. Above 1.5x only (Pangaea, Onion), smooth the land/water edge with a bilinear land fraction ≥ 0.5 test. Bytes still come from the nearest tile.
6. Recompute water bodies, shore bits and water depth with a numpy port of make_maps.postprocess.

`k_lin` is the upstream k_lin divided by the scale. It is in the same sense as sim/real_maps.gd, i.e. full-size upstream tiles per our tile.

## Constraints

- Antarctica (restored 2026-11-09): World source land in rows >= 820 (59.4 S; 207,614 source tiles) is kept and written as code 4 "snow" in codes.bin (166,781 tiles after scaling). Snow is ordinary land: plains rules for movement, conquest, spawns and building, nothing impassable; it is only drawn white (SNOW_COLOR #F4F7FA). tiles.bin keeps the upstream bytes.
- The spawns West Antarctica, Antarctica and East Antarctica (flag `aq`) are kept (World 71 nations).
- Game side: docs/HOOKS.md section Snow (docs/hooks_snow.patch, or tools/apply_snow_hooks.py). Without it, current main.gd treats code 4 as mountain (still white and conquerable, but slower).
- Any 0x9F would also become water, but none exists.
- No capitals: upstream maps only carry spawn points `{name, flag, x, y}`, kept as `[name, flag, x, y]` in this project's format. Every spawn was verified on land.

## Output (maps/upstream/)

- `<id>.codes.bin`: zlib, 1792*1600 u8 (0 water, 1 plains, 2 highland, 3 mountain). This is the same payload as the real_maps.gd b64 strings.
- `<id>.tiles.bin`: zlib, full upstream byte (elevation 0-30, lake vs ocean, water depth) for richer terrain use.
- `<id>.json`: name, categories, crop/scale/k_lin, nations (with source x/y), notes.
- `index.json`: map list, the upstream nation colour table (87 rows, Data/Nations.luau) and the 480 tribe names (Data/Tribes.luau).
- `previews/<id>_small.png`: 448x400, upstream MapSurface palette, terrain only (no spawn markers, labels or captions); snow drawn white. There is a `.gdignore`, so Godot doesn't import them.
- Full-size previews: /workspace/shots/upstream_maps/previews_full/<id>.png
- Contact sheet: /workspace/shots/upstream_maps/contact_sheet.png
- In-game match renders through the hook: /workspace/shots/upstream_maps/31_match_tab2_map0{0,2,5,7}.png

## Not converted

- Map thumbnails (Assets/MapThumbs) are Roblox asset ids only. The previews here replace them.
- The globe (assets/globe/*.glb + PNG) belongs to the old 3D view.
- ArsenalMaps is an image atlas of shop-demo map pieces, Roblox id only.
- The raw Natural Earth / ETOPO inputs are not in the repo (make_maps.py downloads them at build time), so higher-res rebuilds would need /workspace/geo as before.
- sim/real_maps.gd already contained a bicubic re-render of the same 6 game maps. These upstream files are the faithful byte decode, offered as a separate tab, not a replacement.

Contact sheet: `python3 tools/contact_sheet_upstream.py` -> /workspace/shots/upstream_maps/contact_sheet.png (4x2, no captions).

## Geography fixes (tools/mapfix.py, 2026-11-09)

Applied by the converter before postprocess (set `NO_MAPFIX=1` to skip) and to sim/real_maps.gd with `python3 tools/mapfix.py` (re-running is a no-op). Each fix runs on every map whose window shows the place, through the map's own lon/lat projection (make_maps.py windows, convert_maps2.py bboxes).

- Suez Canal: a 2-tile channel Port Said to Suez. It cuts the Africa–Sinai land link. Bab-el-Mandeb was already open on every map. On World (~5 tiles a degree), the cheapest crossing near the real line is cut instead of the line itself.
- Panama Canal: a 2-tile channel Colón to Balboa, done the same way.
- Both canals are then checked as one continuous 4-connected channel at least 2 tiles wide from sea to sea, with no diagonal-only links or 1-tile pinches. Every tile on it sits in an all-water 2x2 block. Where that fails, the cheapest path of 2x2 blocks is cut. This also covers a sea that is only 1 tile wide at that scale, like the World Gulf of Suez. test_mapfix.gd checks the same thing.
- Hawaii, World: the one-blob chain is redrawn from Natural Earth 10m outlines (Hawaiʻi, Maui, Molokaʻi, Lānaʻi, Oʻahu, Kauaʻi). It is scaled ×2.5 about its centre so each island is playable, with water between them. Elevation comes from the coast distance.
- Hawaii, North America: the islands were already separate. Molokaʻi and Lānaʻi, which upstream's 21-tile cleanup had dropped, are added.
- Hainan: the Qiongzhou Strait is opened to at least 2 tiles where the map joined Hainan to Leizhou (World only; Asia and Southeast Asia were already separate).
- Edits per map are listed in `<id>.json` under `mapfix`. No spawn sat on new water.
- Check: `godot --headless --path . -s res://tests/test_mapfix.gd`. Ships route Med→Red Sea through Suez and Caribbean→Pacific through Panama on every map that has them, and the islands are separate land components. Cases come from `python3 tools/mapfix_cases.py`.
