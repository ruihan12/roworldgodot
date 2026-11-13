#!/usr/bin/env python3
"""Decode every RoWorld map (MapCodec: base64 -> zstd -> W*H tile bytes, WorldMap.luau format) and convert
to Frontline Conquest's 1792x1600 grid. Writes maps/upstream/<id>.codes.bin (zlib, 0 water 1 plains
2 highland 3 mountain - the same as sim/real_maps.gd b64 payloads), <id>.tiles.bin (zlib, full upstream
tile byte: bit7 land, bit6 shore, bit5 ocean, bits0-4 magnitude), <id>.json (meta + nations), index.json,
previews/<id>.png. Usage: python3 tools/convert_upstream_maps.py [/path/to/roworld_src]
Source: RoWorld (github.com/lukechatton/roworld, AGPL; maps from Natural Earth + NOAA ETOPO1, public domain).
"""
import base64, json, os, re, sys, zlib
import numpy as np, zstandard
from PIL import Image, ImageDraw
from scipy import ndimage
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mapfix  # geography fixes: Suez, Panama, Hawaii islands, Hainan strait (tools/mapfix.py)

SRC = sys.argv[1] if len(sys.argv) > 1 else "/workspace/roworld_src"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "maps", "upstream")
W, H = 1792, 1600
LAND, SHORE, OCEAN, IMPASSABLE = 0x80, 0x40, 0x20, 0x9F
FOUR = [[0, 1, 0], [1, 1, 1], [0, 1, 0]]
MARGIN = 8
PREVIEW_FULL = os.environ.get("PREVIEW_FULL", "/workspace/shots/upstream_maps/previews_full")  # full-size previews stay out of the project
WORLD_SOUTH_CUT = 820  # upstream's own Antarctica cut (tools/maps/make_fixtures.py PANGAEA_SOUTH_CUT)
FILES = [
    ("src/shared/Data/Maps/World.luau", "game"),
    ("src/server/MapData/Africa.luau", "game"),
    ("src/server/MapData/Asia.luau", "game"),
    ("src/server/MapData/Europe.luau", "game"),
    ("src/server/MapData/NorthAmerica.luau", "game"),
    ("src/server/MapData/SouthAmerica.luau", "game"),
    ("tests/fixtures/maps/Pangaea.luau", "test_fixture"),
    ("tests/fixtures/maps/Onion.luau", "test_fixture"),
]
# Map/MapSurface.luau terrain colours (as tools/assets/make_map_thumbs.py)
C_OCEAN = (0x47, 0x85, 0xB5); C_SAND = (0xCC, 0xCB, 0x9E); C_PLAINS = (0xBE, 0xDC, 0x8A)
C_HIGH = (0xDC, 0xCB, 0x9E); C_MTN = (0xE6, 0xE6, 0xE6); C_SNOW = (0xF4, 0xF7, 0xFA)


def lua_list(s):
    return re.findall(r'"([^"]*)"', s or "")


def parse(path):
    s = open(path, encoding="utf-8").read()
    g = lambda k: re.search(r"^\t%s = (.+?),?$" % k, s, re.M)
    d = {
        "id": g("id").group(1).strip('"'), "name": g("name").group(1).strip('"'),
        "module": g("module").group(1).strip('"'),
        "width": int(g("width").group(1)), "height": int(g("height").group(1)),
        "k_lin": float(g("k_lin").group(1)),
        "categories": lua_list(g("categories").group(1)),
        "multiplayer_frequency": int(g("multiplayer_frequency").group(1)),
        "forced_modifiers": lua_list(g("forced_modifiers").group(1)),
        "land_tiles": int(g("land_tiles").group(1)),
        "codec": (g("codec").group(1).strip('"') if g("codec") else "zstd+base64"),
        "header": [l[3:] for l in s.splitlines() if l.startswith("-- ")],
    }
    d["nations"] = [{"name": m.group(1), "flag": m.group(2), "x": int(m.group(3)), "y": int(m.group(4))}
                    for m in re.finditer(r'\{ name = "([^"]+)", flag = "([^"]*)", x = (\d+), y = (\d+) \}', s)]
    t = re.search(r'\tterrain = "([^"]+)"', s).group(1)
    assert d["codec"] == "zstd+base64", d["codec"]
    raw = zstandard.ZstdDecompressor().decompress(base64.b64decode(t), max_output_size=d["width"] * d["height"])
    assert len(raw) == d["width"] * d["height"], (path, len(raw))
    d["bytes"] = np.frombuffer(raw, np.uint8).reshape(d["height"], d["width"]).copy()
    d["zstd_bytes"] = len(base64.b64decode(t))
    return d


def postprocess(tb):
    """make_maps.postprocess in numpy: ocean = largest water body + bodies touching the edge; shore bits;
    water magnitude = min(ceil(geodesic 4-neighbour distance from shoreline water / 2), 31)."""
    land = (tb & LAND) != 0
    water = ~land
    lab, n = ndimage.label(water, structure=FOUR)
    oceans = set()
    if n:
        sizes = np.bincount(lab.ravel()); sizes[0] = 0
        oceans.add(int(np.argmax(sizes)))
        for e in (lab[0], lab[-1], lab[:, 0], lab[:, -1]):
            oceans.update(int(v) for v in np.unique(e))
        oceans.discard(0)
    is_ocean = np.isin(lab, list(oceans))
    def nb_any(mask):
        o = np.zeros_like(mask)
        o[1:] |= mask[:-1]; o[:-1] |= mask[1:]; o[:, 1:] |= mask[:, :-1]; o[:, :-1] |= mask[:, 1:]
        return o
    shore_land = land & nb_any(water)
    shore_water = water & nb_any(land)
    out = np.where(land, (tb & (LAND | 0x1F)) | np.where(shore_land, SHORE, 0), 0).astype(np.uint8)
    out[water] = np.where(is_ocean[water], OCEAN, 0)
    out[shore_water] |= SHORE
    # geodesic BFS distance over water, capped at 62 (mag 31)
    dist = np.full(tb.shape, 99, np.int16); dist[shore_water] = 0
    front = shore_water.copy(); seen = shore_water.copy()
    for d in range(1, 63):
        nxt = nb_any(front) & water & ~seen
        if not nxt.any(): break
        dist[nxt] = d; seen |= nxt; front = nxt
    mag = np.minimum(np.ceil(np.minimum(dist, 62) / 2.0), 31).astype(np.uint8)
    wm = water & ~shore_water
    out[wm] |= mag[wm]
    # keep upstream's impassable byte if any survived
    out[tb == IMPASSABLE] = IMPASSABLE
    return out


def convert(d):
    tb = d["bytes"].copy()
    notes = []
    h0, w0 = tb.shape
    dropped = []
    snow_src = np.zeros(tb.shape, bool)
    if d["id"] in ("world",):
        # Antarctica kept (user, 2026-11-09) as ordinary land; flagged "snow" (code 4) so the game can
        # draw it white while treating it like plains for movement, conquest, spawns and building.
        snow_src[WORLD_SOUTH_CUT:] = (tb[WORLD_SOUTH_CUT:] & LAND) != 0
        notes.append("Antarctica kept: %d land tiles in rows >= %d (south of 59.4 S) -> code 4 snow (passable, conquerable)" % (int(snow_src.sum()), WORLD_SOUTH_CUT))
    ice = int((tb == IMPASSABLE).sum())
    if ice:
        tb[tb == IMPASSABLE] = OCEAN | 31
        notes.append("%d impassable/ice tiles (0x9F) -> water" % ice)
    nations = []
    for n in d["nations"]:
        nations.append(dict(n))
    if dropped:
        notes.append("nations dropped (Antarctica): " + ", ".join(dropped))
    land = (tb & LAND) != 0
    rows = np.where(land.any(1))[0]; cols = np.where(land.any(0))[0]
    y0 = max(rows[0] - MARGIN, 0); y1 = min(rows[-1] + 1 + MARGIN, h0)
    x0 = max(cols[0] - MARGIN, 0); x1 = min(cols[-1] + 1 + MARGIN, w0)
    tb = tb[y0:y1, x0:x1]; snow_src = snow_src[y0:y1, x0:x1]; ch, cw = tb.shape
    s = min(W / cw, H / ch)
    nw, nh = min(W, int(round(cw * s))), min(H, int(round(ch * s)))
    ox, oy = (W - nw) // 2, (H - nh) // 2
    # upstream WorldMap._resample: each new tile takes the source tile under its centre
    xs = np.minimum(cw - 1, np.floor((np.arange(nw) + 0.5) * cw / nw).astype(int))
    ys = np.minimum(ch - 1, np.floor((np.arange(nh) + 0.5) * ch / nh).astype(int))
    sub = tb[ys][:, xs]
    snow_sub = snow_src[ys][:, xs]
    method = "nearest (upstream WorldMap._resample, centre sampling)"
    if s > 1.5:
        # big upscale: nearest gives s-pixel stair steps; smooth only the land/water edge with a bilinear
        # land-fraction >= 0.5 test, bytes still from the nearest tile (new land beside it gets the max
        # neighbouring land magnitude)
        lf = np.asarray(Image.fromarray(((tb & LAND) != 0).astype(np.float32), "F").resize((nw, nh), Image.BILINEAR))
        nl = lf >= 0.5
        landmag = np.where((sub & LAND) != 0, sub & 0x1F, 0).astype(np.uint8)
        grown = landmag.copy()
        for _ in range(3):
            grown = np.where((sub & LAND) != 0, landmag, ndimage.grey_dilation(grown, footprint=FOUR))
        sub = np.where(nl, LAND | np.where((sub & LAND) != 0, sub & 0x1F, grown), 0).astype(np.uint8)
        method = "nearest bytes + bilinear land-edge smoothing (upscale %.2fx)" % s
    full = np.full((H, W), OCEAN | 31, np.uint8)
    full[oy:oy + nh, ox:ox + nw] = sub
    snow = np.zeros((H, W), bool)
    snow[oy:oy + nh, ox:ox + nw] = snow_sub
    fixes = []
    if d["id"] in mapfix.SPEC and os.environ.get("NO_MAPFIX") != "1":
        land0 = (full & LAND) != 0
        land1, fixes, added = mapfix.apply(land0, mapfix.geo_upstream(d["id"], [x0, y0, x1, y1], [ox, oy, nw, nh]), d["id"])
        rem = land0 & ~land1
        full[rem] = OCEAN | 31
        full[added] = LAND | mapfix.island_mag(added)[added]
        snow[rem | added] = False
        for f in fixes:
            notes.append("mapfix %s: %s" % (f["fix"], ", ".join("%s %s" % (k, v) for k, v in f.items() if k != "fix")))
    full = postprocess(full)
    for n in nations:
        n["src_x"], n["src_y"] = n["x"], n["y"]
        x = int(min(nw - 1, max(0, np.floor((n["x"] - x0 + 0.5) * nw / cw)))) + ox
        y = int(min(nh - 1, max(0, np.floor((n["y"] - y0 + 0.5) * nh / ch)))) + oy
        if not full[y, x] & LAND:
            yy, xx = np.nonzero((full & LAND) != 0)
            k = int(np.argmin((yy - y) ** 2 + (xx - x) ** 2)); x, y = int(xx[k]), int(yy[k])
            n["moved_to_land"] = True
        n["x"], n["y"] = x, y
    mag = full & 0x1F
    isl = (full & LAND) != 0
    codes = np.where(isl, np.where(mag < 10, 1, np.where(mag < 20, 2, 3)), 0).astype(np.uint8)
    codes[isl & snow] = 4  # snow: plains for gameplay, white on screen
    lab, nlab = ndimage.label(~isl, structure=FOUR)
    meta = {k: d[k] for k in ("id", "name", "module", "categories", "multiplayer_frequency", "forced_modifiers")}
    meta.update({
        "source_file": d["path"], "source_kind": d["kind"], "source_header": d["header"],
        "src_width": w0, "src_height": h0, "src_k_lin": d["k_lin"], "src_land_tiles": d["land_tiles"],
        "src_land_tiles_decoded": int(((d["bytes"] & LAND) != 0).sum() - (d["bytes"] == IMPASSABLE).sum()),
        "src_impassable_tiles": int((d["bytes"] == IMPASSABLE).sum()),
        "crop": [int(x0), int(y0), int(x1), int(y1)], "scale": round(s, 6), "placed": [ox, oy, nw, nh],
        "width": W, "height": H, "k_lin": round(d["k_lin"] / s, 4), "resample": method,
        "land_tiles": int(isl.sum()), "code_counts": [int((codes == c).sum()) for c in range(5)], "snow_tiles": int((codes == 4).sum()),
        "lake_tiles": int(((~isl) & ((full & OCEAN) == 0)).sum()), "water_bodies": int(nlab),
        "nations": nations, "notes": notes, "mapfix": fixes,
    })
    return meta, codes, full


def preview(meta, full, path, small):
    land = full >= 128; shore = (full & SHORE) != 0; mag = (full & 0x1F).astype(np.int32)
    img = np.zeros(full.shape + (3,), np.int32)
    pl = land & (mag < 10); hl = land & (mag >= 10) & (mag < 20); mt = land & (mag >= 20)
    img[pl] = np.stack([np.full(pl.sum(), C_PLAINS[0]), C_PLAINS[1] - 2 * mag[pl], np.full(pl.sum(), C_PLAINS[2])], -1)
    img[hl] = np.array(C_HIGH)[None] + 2 * (mag[hl] - 10)[:, None]
    img[mt] = np.array(C_MTN)[None] + (mag[mt] // 2)[:, None]
    img[land & shore] = C_SAND
    if "snow" in meta: img[meta["snow"]] = C_SNOW
    w = ~land
    img[w] = np.array(C_OCEAN)[None] - (np.minimum(mag[w], 10) + 0.6 * np.maximum(0, mag[w] - 10))[:, None]
    img[w & shore] = (np.array(C_OCEAN) * 0.7 + 76.5).astype(int)
    lake = w & ((full & OCEAN) == 0)
    img[lake & ~shore] = (88, 150, 200)
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    # clean terrain only: no spawn markers, labels or captions (user, 2026-11-09)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path)
    im.resize((W // 4, H // 4), Image.LANCZOS).save(small)


def main():
    os.makedirs(os.path.join(OUT, "previews"), exist_ok=True)
    index = []
    for rel, kind in FILES:
        p = os.path.join(SRC, rel)
        d = parse(p); d["path"] = rel; d["kind"] = kind
        meta, codes, full = convert(d)
        open(os.path.join(OUT, meta["id"] + ".codes.bin"), "wb").write(zlib.compress(codes.tobytes(), 9))
        open(os.path.join(OUT, meta["id"] + ".tiles.bin"), "wb").write(zlib.compress(full.tobytes(), 9))
        meta.pop("snow", None)
        json.dump(meta, open(os.path.join(OUT, meta["id"] + ".json"), "w"), indent=1, ensure_ascii=False)
        meta["snow"] = codes == 4
        preview(meta, full, os.path.join(PREVIEW_FULL, meta["id"] + ".png"), os.path.join(OUT, "previews", meta["id"] + "_small.png"))
        index.append({k: meta[k] for k in ("id", "name", "source_kind", "categories", "k_lin", "scale", "land_tiles")}
                     | {"nations": len(meta["nations"]), "src_size": [meta["src_width"], meta["src_height"]]})
        print("%-14s src %dx%d (land %d, decoded %d, 0x9F %d) crop %s scale %.3f -> land %d, nations %d, %s %s"
              % (meta["name"], meta["src_width"], meta["src_height"], meta["src_land_tiles"], meta["src_land_tiles_decoded"],
                 meta["src_impassable_tiles"], meta["crop"], meta["scale"], meta["land_tiles"], len(meta["nations"]), meta["resample"], meta["notes"]))
    # shared tables: nation colours (Data/Nations.luau), tribe names (Data/Tribes.luau)
    ns = open(os.path.join(SRC, "src/shared/Data/Nations.luau"), encoding="utf-8").read()
    nat = [{"name": m.group(1), "code": m.group(2), "lat": float(m.group(3)), "lon": float(m.group(4)), "color": m.group(5)}
           for m in re.finditer(r'name = "([^"]+)", code = "(\w+)", lat = ([-\d.]+), lon = ([-\d.]+), x = \d+, y = \d+, color = "(#\w+)"', ns)]
    tr = open(os.path.join(SRC, "src/shared/Data/Tribes.luau"), encoding="utf-8").read()
    tribes = re.findall(r'^\t\t"([^"]+)",$', tr, re.M)
    json.dump({"source": "RoWorld @ ae7a350 (AGPL); maps: Natural Earth + NOAA ETOPO1 (public domain)",
               "format": {"width": W, "height": H, "codes": "zlib(W*H u8): 0 water 1 plains 2 highland 3 mountain 4 snow (Antarctica: plains rules, white colour)",
                          "tiles": "zlib(W*H u8) upstream tile byte: bit7 land, bit6 shore, bit5 ocean, bits0-4 magnitude"},
               "default": "world", "maps": index, "nation_table": nat, "tribe_names": tribes},
              open(os.path.join(OUT, "index.json"), "w"), indent=1, ensure_ascii=False)
    print("nation_table", len(nat), "tribes", len(tribes))


if __name__ == "__main__":
    main()
