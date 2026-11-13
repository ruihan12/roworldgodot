#!/usr/bin/env python3
"""Writes tests/mapfix_cases.json for tests/test_mapfix.gd: per map tab/index, a ship route through each canal
(Mediterranean -> Red Sea via Suez, Caribbean -> Pacific via Panama) as water tiles, the canal's middle tile
and how close the route must pass; plus the Hainan / Hawaii island probes."""
import base64, json, os, re, sys, zlib
import numpy as np
from scipy import ndimage
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mapfix
ROOT = mapfix.ROOT; W, H = mapfix.W, mapfix.H
UP_ORDER = ["world", "europe", "asia", "northamerica", "southamerica", "africa", "pangaea", "onion"]
TAB0 = {0: ("up", "world"), 2: ("rm", "med"), 3: ("rm", "asia"), 4: ("rm", "northamerica"), 5: ("rm", "southamerica"),
        6: ("rm", "africa"), 7: ("rm", "mideast"), 8: ("rm", "seasia"), 10: ("rm", "carib")}
ROUTES = {"suez": [(30.5, 33.2), (34.6, 27.4)], "panama": [(-79.0, 11.0), (-79.6, 7.2)]}
MID = {"suez": (32.33, 30.4), "panama": (-79.7, 9.1)}
ISLANDS = {"hainan": [(109.8, 19.1), (110.1, 21.0)], "hawaii": [(-155.5, 19.6), (-156.3, 20.8), (-158.0, 21.45), (-159.5, 22.05)]}


def nearest(mask, x, y):
    yy, xx = np.nonzero(mask); k = int(np.argmin((yy - y) ** 2 + (xx - x) ** 2)); return int(yy[k]) * W + int(xx[k])


def main():
    rm = {}
    s = open(os.path.join(ROOT, "sim", "real_maps.gd")).read()
    for e in json.loads(s.split("const MAPS := ", 1)[1].split("\nconst NATION_COLORS", 1)[0]):
        rm[e["id"]] = np.frombuffer(zlib.decompress(base64.b64decode(e["b64"])), np.uint8).reshape(H, W)
    cfgs = [(2, k, "up", m) for k, m in enumerate(UP_ORDER) if m in mapfix.SPEC] + [(0, k, a, b) for k, (a, b) in TAB0.items()]
    cases = []
    for tab, k, kind, mid in cfgs:
        if kind == "up":
            meta = json.load(open(os.path.join(ROOT, "maps", "upstream", mid + ".json")))
            c = np.frombuffer(zlib.decompress(open(os.path.join(ROOT, "maps", "upstream", mid + ".codes.bin"), "rb").read()), np.uint8).reshape(H, W)
            geo = mapfix.geo_upstream(mid, meta["crop"], meta["placed"])
        else:
            c = rm[mid]; geo = mapfix.geo_realmap(mid, "/workspace/roworld_src")
        tpd = abs(geo(10.0, 0.0)[0] - geo(11.0, 0.0)[0])
        e = {"tab": tab, "k": k, "map": kind + ":" + mid, "routes": [], "islands": []}
        for nm, (a, b) in ROUTES.items():
            pts = [geo(*a), geo(*b), geo(*MID[nm])]
            if not all(0 <= x < W and 0 <= y < H for x, y in pts): continue
            ln = mapfix.CANALS[nm]["line"]
            half = max(abs(geo(*ln[0])[1] - geo(*ln[-1])[1]), abs(geo(*ln[0])[0] - geo(*ln[-1])[0])) / 2
            # 2-wide check window and one wide-water tile in each sea (tools/mapfix.py canal_ok window)
            cp = [geo(*q) for q in ln]; sd = [geo(*q) for q in mapfix.CANALS[nm]["seeds"]]
            win = mapfix._grow(mapfix._window(cp, 8 if tpd < 8 else int(tpd * 0.4) + 4, sd), 8)
            x0, x1, y0, y1 = win
            ww = mapfix.wide_water(c[y0:y1, x0:x1] == 0)
            ends = []
            for sx, sy in sd:
                q = mapfix._nearest(ww, sx - x0, sy - y0); ends.append((q[1] + y0) * W + q[0] + x0)
            e["routes"].append({"name": nm, "src": nearest(c == 0, *pts[0]), "dst": nearest(c == 0, *pts[1]),
                                "mid": int(pts[2][1]) * W + int(pts[2][0]), "max_d": round(half + 4 + tpd * 0.05, 1),
                                "win": [int(x0), int(x1), int(y0), int(y1)], "sea_a": ends[0], "sea_b": ends[1]})
        for nm, ps in ISLANDS.items():
            if nm == "hawaii" and mid == "world":  # chain redrawn x scale about its centre (tools/mapfix.py)
                f = mapfix.hawaii_scale(geo); cx, cy = mapfix.HAWAII_CENTRE
                ps = [(cx + (lo - cx) * f, cy + (la - cy) * f) for lo, la in ps]
            q = [geo(*p) for p in ps]
            if not all(0 <= x < W and 0 <= y < H for x, y in q): continue
            e["islands"].append({"name": nm, "tiles": [nearest(c > 0, x, y) for x, y in q]})
        cases.append(e)
    json.dump(cases, open(os.path.join(ROOT, "tests", "mapfix_cases.json"), "w"), indent=1)
    print(len(cases), "maps")


if __name__ == "__main__":
    main()
