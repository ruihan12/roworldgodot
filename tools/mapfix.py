#!/usr/bin/env python3
"""Geography fixes applied on top of the decoded maps (user request 2026-11-09):
  - Suez Canal: 2-tile channel Port Said -> Suez (Mediterranean <-> Red Sea; Bab-el-Mandeb already open)
  - Panama Canal: 2-tile channel Colon -> Balboa (Caribbean <-> Pacific)
  - Hawaii: separate islands (Hawai'i, Maui, Molokai, Lanai, O'ahu, Kaua'i), redrawn from Natural Earth 10m
    outlines where the map shows the chain as one blob (World: archipelago scaled x2.5 about its centre so
    each island is playable; North America: the two islands upstream's 21-tile cleanup dropped are added)
  - Hainan: Qiongzhou Strait opened (>= 2 tiles of water between Hainan and the Leizhou peninsula)
Works on a boolean land mask through a lon/lat -> map tile function, so the same fixes run on the upstream
maps (tools/convert_upstream_maps.py, before postprocess) and on sim/real_maps.gd (python3 tools/mapfix.py).
Idempotent: running it on an already fixed map changes nothing.
"""
import base64, json, math, os, re, sys, zlib
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

FOUR = [[0, 1, 0], [1, 1, 1], [0, 1, 0]]
EIGHT = np.ones((3, 3), bool)
W, H = 1792, 1600

# Equirectangular windows of the upstream maps (roworld tools/maps/make_maps.py MAPS) and the bounding boxes
# of the port's regional maps (/workspace/roworld_port/convert_maps2.py BB: lat0, lat1, lon0, lon1).
SPEC = {
    "world": dict(lon0=-180.0 + 65 / (2000 / 360.0), lat_top=90.0 - 10 / (2000 / 360.0), ppd=2000 / 360.0, lat_std=0.0),
    "europe": dict(lon0=-25.0, lat_top=72.0, ppd=33.0, lat_std=52.0),
    "northamerica": dict(lon0=-170.0, lat_top=75.0, ppd=18.0, lat_std=40.0),
    "southamerica": dict(lon0=-92.0, lat_top=14.0, ppd=20.0, lat_std=-20.0),
    "asia": dict(lon0=25.0, lat_top=78.0, ppd=15.0, lat_std=35.0),
    "africa": dict(lon0=-26.0, lat_top=38.0, ppd=18.0, lat_std=10.0),
}
BB = {"med": (26, 50, -7, 37), "mideast": (12, 44, 25, 63), "seasia": (-11, 24, 92, 128),
      "brit": (48, 62, -12, 14), "carib": (4, 34, -100, -58), "aegean": (33, 49, 19, 44)}

# canal centre lines (lon, lat), and a water seed at each end (the sea the end must open into)
CANALS = {
    "suez": dict(line=[(32.30, 31.32), (32.31, 30.95), (32.28, 30.62), (32.33, 30.40), (32.42, 30.30), (32.55, 30.05), (32.56, 29.90)],
                 seeds=[(32.3, 31.6), (32.75, 29.0)]),
    "panama": dict(line=[(-79.95, 9.42), (-79.92, 9.27), (-79.82, 9.18), (-79.68, 9.10), (-79.62, 9.02), (-79.56, 8.94), (-79.52, 8.82)],
                   seeds=[(-79.85, 9.6), (-79.45, 8.6)]),
}
HAINAN = dict(lon=(108.4, 111.3), lat=(18.0, 21.2), strait_lat=20.17, probe_h=(109.8, 19.1), probe_m=(110.1, 21.0))
# Natural Earth 10m land outlines (simplified)
HAWAII = {
    "hawaii": [(-154.9, 19.567), (-154.817, 19.48), (-154.982, 19.339), (-155.093, 19.286), (-155.269, 19.266), (-155.364, 19.204), (-155.437, 19.17), (-155.554, 19.082), (-155.619, 18.956), (-155.684, 18.911), (-155.792, 18.997), (-155.884, 19.047), (-155.92, 19.139), (-155.901, 19.383), (-155.946, 19.494), (-155.971, 19.58), (-156.036, 19.668), (-156.017, 19.801), (-155.968, 19.854), (-155.873, 19.951), (-155.824, 20.02), (-155.897, 20.149), (-155.867, 20.263), (-155.733, 20.239), (-155.673, 20.182), (-155.586, 20.123), (-155.421, 20.09), (-155.116, 19.897), (-155.085, 19.727), (-154.977, 19.706)],
    "maui": [(-156.002, 20.8), (-156.003, 20.686), (-156.075, 20.651), (-156.185, 20.627), (-156.285, 20.589), (-156.336, 20.588), (-156.408, 20.587), (-156.452, 20.636), (-156.45, 20.726), (-156.464, 20.781), (-156.486, 20.797), (-156.521, 20.776), (-156.563, 20.792), (-156.62, 20.807), (-156.685, 20.882), (-156.692, 20.936), (-156.666, 21.003), (-156.645, 21.021), (-156.616, 21.025), (-156.598, 21.033), (-156.571, 21.016), (-156.538, 20.991), (-156.523, 20.962), (-156.493, 20.922), (-156.453, 20.918), (-156.39, 20.922), (-156.331, 20.951), (-156.282, 20.95), (-156.261, 20.944), (-156.243, 20.942), (-156.215, 20.915), (-156.179, 20.883), (-156.153, 20.862), (-156.131, 20.857), (-156.085, 20.831)],
    "molokai": [(-156.749, 21.171), (-156.733, 21.169), (-156.729, 21.161), (-156.706, 21.157), (-156.756, 21.096), (-156.831, 21.061), (-156.909, 21.057), (-157.025, 21.084), (-157.14, 21.094), (-157.223, 21.087), (-157.273, 21.087), (-157.304, 21.11), (-157.296, 21.144), (-157.267, 21.163), (-157.247, 21.2), (-157.26, 21.222), (-157.233, 21.219), (-157.197, 21.217), (-157.174, 21.205), (-157.028, 21.185), (-156.982, 21.194), (-156.976, 21.211), (-156.952, 21.197), (-156.925, 21.171), (-156.847, 21.167), (-156.811, 21.174), (-156.792, 21.176), (-156.759, 21.173)],
    "lanai": [(-156.848, 20.877), (-156.833, 20.861), (-156.816, 20.842), (-156.806, 20.825), (-156.804, 20.813), (-156.81, 20.795), (-156.831, 20.764), (-156.877, 20.744), (-156.914, 20.735), (-156.962, 20.732), (-156.982, 20.759), (-156.987, 20.783), (-156.988, 20.801), (-156.989, 20.825), (-156.992, 20.846), (-157.009, 20.856), (-157.051, 20.871), (-157.063, 20.89), (-157.055, 20.911), (-157.032, 20.923), (-156.99, 20.928), (-156.893, 20.914)],
    "oahu": [(-157.707, 21.352), (-157.659, 21.294), (-157.707, 21.275), (-157.795, 21.255), (-157.864, 21.29), (-157.902, 21.328), (-157.94, 21.311), (-157.965, 21.341), (-157.932, 21.372), (-157.969, 21.372), (-157.984, 21.362), (-157.997, 21.351), (-158.022, 21.308), (-158.103, 21.299), (-158.157, 21.395), (-158.216, 21.466), (-158.279, 21.575), (-158.149, 21.586), (-158.095, 21.614), (-158.051, 21.671), (-157.962, 21.705), (-157.925, 21.663), (-157.894, 21.598), (-157.864, 21.56), (-157.836, 21.511), (-157.842, 21.461), (-157.788, 21.424), (-157.775, 21.443), (-157.723, 21.452), (-157.709, 21.384)],
    "kauai": [(-159.301, 22.151), (-159.295, 22.108), (-159.333, 22.05), (-159.331, 21.985), (-159.348, 21.958), (-159.348, 21.937), (-159.382, 21.917), (-159.415, 21.888), (-159.434, 21.874), (-159.509, 21.886), (-159.582, 21.894), (-159.596, 21.894), (-159.623, 21.905), (-159.646, 21.932), (-159.666, 21.95), (-159.712, 21.964), (-159.76, 21.979), (-159.78, 22.009), (-159.786, 22.045), (-159.777, 22.07), (-159.734, 22.125), (-159.726, 22.144), (-159.694, 22.164), (-159.621, 22.2), (-159.577, 22.226), (-159.548, 22.231), (-159.53, 22.218), (-159.499, 22.209), (-159.481, 22.23), (-159.429, 22.221), (-159.4, 22.235), (-159.358, 22.223), (-159.319, 22.186), (-159.305, 22.161)],
}
HAWAII_CENTRE = (-157.3, 20.6)
HAWAII_BOX = (-160.5, -154.5, 18.6, 22.6)  # lon0, lon1, lat0, lat1 of the real chain (Niihau and Kahoolawe left out)
HAWAII_MIN_TILES = 20  # World: scale the chain until the smallest of Maui / O'ahu / Kaua'i has about this many tiles


def src_xy(mid, lon, lat):
    s = SPEC[mid]; py = s["ppd"]; px = py * math.cos(math.radians(s["lat_std"]))
    return (lon - s["lon0"]) * px, (s["lat_top"] - lat) * py


def geo_upstream(mid, crop, placed):
    """lon/lat -> tile of a map made by convert_upstream_maps (crop x0,y0,x1,y1 of the source; placed ox,oy,nw,nh)."""
    x0, y0, x1, y1 = crop; ox, oy, nw, nh = placed
    def f(lon, lat):
        sx, sy = src_xy(mid, lon, lat)
        return (sx - x0) * nw / (x1 - x0) + ox, (sy - y0) * nh / (y1 - y0) + oy
    return f


def geo_bbox(mid):
    la0, la1, lo0, lo1 = BB[mid]
    cl = math.cos(math.radians((la0 + la1) / 2)); wk = (lo1 - lo0) * cl; hk = la1 - la0
    sc = min(W / wk, H / hk); nw, nh = int(wk * sc), int(hk * sc); ox, oy = (W - nw) // 2, (H - nh) // 2
    return lambda lon, lat: ((lon - lo0) / (lo1 - lo0) * nw + ox, (la1 - lat) / (la1 - la0) * nh + oy)


def _inside(geo, lon, lat, pad=0):
    x, y = geo(lon, lat)
    return pad <= x < W - pad and pad <= y < H - pad


def _brush(mask, x, y):
    """2x2 tiles centred on (x, y): a 2-wide, 4-connected channel along any direction."""
    ix, iy = int(math.floor(x - 0.5)), int(math.floor(y - 0.5))
    mask[max(iy, 0):max(iy + 2, 0), max(ix, 0):max(ix + 2, 0)] = True


def _stroke(mask, pts):
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        n = int(max(abs(bx - ax), abs(by - ay)) * 4) + 1
        for s in range(n + 1):
            _brush(mask, ax + (bx - ax) * s / n, ay + (by - ay) * s / n)


def _nearest(mask, x, y):
    yy, xx = np.nonzero(mask)
    if not len(yy): return None
    k = int(np.argmin((yy - y) ** 2 + (xx - x) ** 2)); return int(xx[k]), int(yy[k])


def _seg_dist(px, py, pts):
    best = 1e9
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        dx, dy = bx - ax, by - ay; L = dx * dx + dy * dy or 1e-9
        t = min(1, max(0, ((px - ax) * dx + (py - ay) * dy) / L))
        best = min(best, math.hypot(px - ax - t * dx, py - ay - t * dy))
    return best


def _window(pts, R, extra=()):
    xs = [p[0] for p in list(pts) + list(extra)]; ys = [p[1] for p in list(pts) + list(extra)]
    return int(max(0, min(xs) - R)), int(min(W, max(xs) + R + 1)), int(max(0, min(ys) - R)), int(min(H, max(ys) + R + 1))


def _local_bodies(land, win, seeds):
    """water labelled inside the window only (the two seas are one ocean far away; here they must meet)"""
    x0, x1, y0, y1 = win
    lab, _ = ndimage.label(~land[y0:y1, x0:x1], structure=FOUR)
    ids = []
    for sx, sy in seeds:
        p = _nearest(lab > 0, sx - x0, sy - y0)
        ids.append(int(lab[p[1], p[0]]) if p else 0)
    return lab, ids


def _min_crossing(land, pts, seeds, win):
    """Coarse maps (World, ~5 tiles a degree): the real canal line runs along the coarse isthmus, so cut the
    cheapest crossing near it instead: Dijkstra in a window round the line, 1 per land tile + 0.3 per tile
    away from the line, from the first sea to the second; each crossing tile gets a side neighbour (2 wide)."""
    import heapq
    x0, x1, y0, y1 = win
    sl, (ba, bb) = _local_bodies(land, win, seeds)
    if not ba or not bb or ba == bb: return np.zeros_like(land)
    sub = land[y0:y1, x0:x1]
    h, w = sub.shape
    pen = np.array([[_seg_dist(x0 + i + 0.5, y0 + j + 0.5, pts) for i in range(w)] for j in range(h)])
    dist = np.full((h, w), np.inf); prev = {}
    pq = []
    for j, i in zip(*np.nonzero(sl == ba)):
        dist[j, i] = 0; heapq.heappush(pq, (0.0, int(j), int(i)))
    end = None
    while pq:
        d, j, i = heapq.heappop(pq)
        if d > dist[j, i]: continue
        if sl[j, i] == bb: end = (j, i); break
        for dj, di in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nj, ni = j + dj, i + di
            if 0 <= nj < h and 0 <= ni < w:
                nd = d + ((1.0 + 0.3 * pen[nj, ni]) if sub[nj, ni] else 0.01)
                if nd < dist[nj, ni]: dist[nj, ni] = nd; prev[(nj, ni)] = (j, i); heapq.heappush(pq, (nd, nj, ni))
    if end is None: return None
    path = []; k = end
    while k in prev: path.append(k); k = prev[k]
    cut = np.zeros_like(land)
    land_path = [(j, i) for j, i in path if sub[j, i]]
    for j, i in land_path:
        cut[y0 + j, x0 + i] = True
    if land_path:
        dj = abs(land_path[0][0] - land_path[-1][0]); di = abs(land_path[0][1] - land_path[-1][1])
        off = (0, 1) if dj >= di else (1, 0)  # crossing mostly north-south -> widen east, else south
        for j, i in land_path:
            cut[min(H - 1, y0 + j + off[0]), min(W - 1, x0 + i + off[1])] = True
    return cut & land


def carve_canal(land, geo, name):
    c = CANALS[name]
    if not all(_inside(geo, *p, pad=2) for p in c["line"]): return None
    pts = [geo(*p) for p in c["line"]]
    seeds = [geo(*s) for s in c["seeds"]]
    tpd = abs(geo(10.0, 0.0)[0] - geo(11.0, 0.0)[0])
    R = 8 if tpd < 8 else int(tpd * 0.4) + 4
    win = _window(pts, R, seeds)
    if tpd < 8:
        cut = _min_crossing(land, pts, seeds, win)
        if cut is None: return None
        new = _widen(land, land & ~cut, pts, seeds, win)
        return new, land & ~new
    cut = np.zeros_like(land); _stroke(cut, pts)
    new = land & ~cut
    # open each end into its own sea (local water body of its seed) if the line stops short of it
    for k, (ex, ey) in ((0, pts[0]), (1, pts[-1])):
        for _ in range(4):
            lab, ids = _local_bodies(new, win, seeds)
            x0, x1, y0, y1 = win
            if not ids[k]: return None
            if (lab[cut[y0:y1, x0:x1]] == ids[k]).any(): break  # the cut is water now: in that sea's body?
            tgt = _nearest(lab == ids[k], ex - x0, ey - y0)
            _stroke(cut, [(ex, ey), (tgt[0] + x0 + 0.5, tgt[1] + y0 + 0.5)])
            new = land & ~cut
    new = _widen(land, new, pts, seeds, win)
    return new, land & ~new


def wide_water(water):
    """tiles that lie in some all-water 2x2 block: a 4-connected path over these is >= 2 tiles wide"""
    b = water[:-1, :-1] & water[1:, :-1] & water[:-1, 1:] & water[1:, 1:]
    out = np.zeros_like(water)
    out[:-1, :-1] |= b; out[1:, :-1] |= b; out[:-1, 1:] |= b; out[1:, 1:] |= b
    return out


def _sea_ids(land0, win, seeds):
    """window water labels (land0) and, per seed, the label of the nearest tile in an all-water 2x2 block:
    the sea itself, not a 1-tile pocket of coast water next to the seed"""
    x0, x1, y0, y1 = win
    water = ~land0[y0:y1, x0:x1]
    lab, _ = ndimage.label(water, structure=FOUR)
    ww = wide_water(water)
    ids = []
    for sx, sy in seeds:
        p = _nearest(ww, sx - x0, sy - y0)
        ids.append(int(lab[p[1], p[0]]) if p else 0)
    return lab, ids


def _grow(win, m):
    x0, x1, y0, y1 = win
    return max(0, x0 - m), min(W, x1 + m), max(0, y0 - m), min(H, y1 + m)


def _widen(land0, land, pts, seeds, win):
    """Make the canal one continuous 4-connected channel >= 2 tiles wide from sea to sea (no diagonal-only
    links, no 1-tile pinches, also where the sea it opens into is itself 1 tile wide at this scale).
    Dijkstra over 2x2 blocks (neighbouring blocks overlap by 2 tiles, so a block path is a 2-wide orthogonal
    channel) from the all-water blocks of the first sea to those of the second (seas as they were before the
    canal, inside the window); a block costs its land tiles (+0.3 per tile off the canal line), water 0.01.
    The land of the cheapest block path becomes water. No-op when the 2-wide channel already exists."""
    import heapq
    win = _grow(win, 8)
    x0, x1, y0, y1 = win
    lab0, (ia, ib) = _sea_ids(land0, win, seeds)
    if not ia or not ib or ia == ib: return land
    sub = land[y0:y1, x0:x1]
    ww = wide_water(~sub)
    wl, _ = ndimage.label(ww, structure=FOUR)
    if (set(np.unique(wl[(lab0 == ia) & ww]).tolist()) & set(np.unique(wl[(lab0 == ib) & ww]).tolist())) - {0}:
        return land  # already one 2-wide orthogonal channel from sea to sea
    h, w = sub.shape
    def blocks(m):
        return m[:-1, :-1] & m[1:, :-1] & m[:-1, 1:] & m[1:, 1:]
    start = blocks(lab0 == ia); goal = blocks(lab0 == ib)
    if not start.any() or not goal.any(): return land
    lt = sub.astype(np.float32)
    pen = np.array([[_seg_dist(x0 + i + 0.5, y0 + j + 0.5, pts) for i in range(w)] for j in range(h)], np.float32)
    tcost = lt * (1.0 + 0.3 * pen)
    bcost = tcost[:-1, :-1] + tcost[1:, :-1] + tcost[:-1, 1:] + tcost[1:, 1:] + 0.01
    bh, bw = bcost.shape
    dist = np.full((bh, bw), np.inf); prev = {}
    pq = []
    for j, i in zip(*np.nonzero(start)):
        dist[j, i] = 0.0; heapq.heappush(pq, (0.0, int(j), int(i)))
    end = None
    while pq:
        d, j, i = heapq.heappop(pq)
        if d > dist[j, i]: continue
        if goal[j, i]: end = (j, i); break
        for dj, di in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nj, ni = j + dj, i + di
            if 0 <= nj < bh and 0 <= ni < bw:
                nd = d + float(bcost[nj, ni])
                if nd < dist[nj, ni]: dist[nj, ni] = nd; prev[(nj, ni)] = (j, i); heapq.heappush(pq, (nd, nj, ni))
    if end is None: return land
    out = land.copy(); k = end
    while True:
        j, i = k
        out[y0 + j:y0 + j + 2, x0 + i:x0 + i + 2] = False
        if k not in prev: break
        k = prev[k]
    return out


def canal_ok(land0, land, geo, name):
    """True when the two seas of the canal meet through 2-wide (wide_water) tiles, 4-connected, in the window"""
    c = CANALS[name]
    pts = [geo(*p) for p in c["line"]]; seeds = [geo(*s) for s in c["seeds"]]
    tpd = abs(geo(10.0, 0.0)[0] - geo(11.0, 0.0)[0])
    win = _grow(_window(pts, 8 if tpd < 8 else int(tpd * 0.4) + 4, seeds), 8)
    x0, x1, y0, y1 = win
    lab0, (ia, ib) = _sea_ids(land0, win, seeds)
    ww = wide_water(~land[y0:y1, x0:x1])
    lab, _ = ndimage.label(ww, structure=FOUR)
    a = set(np.unique(lab[(lab0 == ia) & ww]).tolist()) - {0}
    b = set(np.unique(lab[(lab0 == ib) & ww]).tolist()) - {0}
    return bool(a & b)


def open_hainan(land, geo):
    h = HAINAN
    if not (_inside(geo, *h["probe_h"]) and _inside(geo, *h["probe_m"])): return None
    x0, y1 = geo(h["lon"][0], h["lat"][0]); x1, y0 = geo(h["lon"][1], h["lat"][1])
    x0, x1, y0, y1 = int(max(0, x0)), int(min(W, x1 + 1)), int(max(0, y0)), int(min(H, y1 + 1))
    _, ys = geo(h["lon"][0], h["strait_lat"])
    sub = land[y0:y1, x0:x1]
    rows = (np.arange(y0, y1) + 0.5)[:, None] * np.ones((1, x1 - x0))
    isl = sub & (rows > ys)   # south of the strait line: Hainan
    main = sub & (rows <= ys)
    near_main = ndimage.binary_dilation(main, EIGHT)
    near_isl = ndimage.binary_dilation(isl, EIGHT)
    # >= 2 water tiles across: drop the tiles of each side that touch (8-way) the other side
    cut = (isl & near_main) | (main & near_isl)
    if not cut.any(): return land, np.zeros_like(land)
    new = land.copy(); new[y0:y1, x0:x1] &= ~cut
    return new, land & ~new


def _island_masks(geo, scale, names):
    cx, cy = HAWAII_CENTRE
    out = {}
    for nm in names:
        ring = [(cx + (lo - cx) * scale, cy + (la - cy) * scale) for lo, la in HAWAII[nm]]
        q = [geo(lo, la) for lo, la in ring]
        xs = [p[0] for p in q]; ys = [p[1] for p in q]
        bx0, by0 = int(math.floor(min(xs))) - 2, int(math.floor(min(ys))) - 2
        bx1, by1 = int(math.ceil(max(xs))) + 3, int(math.ceil(max(ys))) + 3
        SS = 8
        im = Image.new("L", ((bx1 - bx0) * SS, (by1 - by0) * SS), 0)
        ImageDraw.Draw(im).polygon([((x - bx0) * SS, (y - by0) * SS) for x, y in q], fill=255)
        frac = np.asarray(im.resize((bx1 - bx0, by1 - by0), Image.BOX), np.float32) / 255
        m = np.zeros((H, W), bool)
        sub = frac >= 0.45
        if sub.sum() == 0:  # thinner than a tile: keep its fullest tile
            sub = frac >= frac.max() * 0.999
        ys_, xs_ = np.nonzero(sub)
        ok = (ys_ + by0 >= 0) & (ys_ + by0 < H) & (xs_ + bx0 >= 0) & (xs_ + bx0 < W)
        m[ys_[ok] + by0, xs_[ok] + bx0] = True
        out[nm] = m
    return out


def _separate(masks, keep=None):
    """Every island its own 4-connected blob with >= 1 water tile (8-way) to any other island: tiles of the
    smaller one next to a bigger one become water."""
    names = sorted(masks, key=lambda k: -masks[k].sum())
    taken = np.zeros((H, W), bool) if keep is None else keep.copy()
    for nm in names:
        m = masks[nm] & ~ndimage.binary_dilation(taken, EIGHT)
        lab, n = ndimage.label(m, structure=FOUR)
        if n > 1:
            s = np.bincount(lab.ravel()); s[0] = 0; m = lab == int(np.argmax(s))
        masks[nm] = m; taken |= m
    return masks


def hawaii_scale(geo):
    """World: smallest x0.25 step that gives Maui, O'ahu and Kaua'i >= HAWAII_MIN_TILES tiles each"""
    scale = 1.0
    while scale < 4.0:
        ms = _island_masks(geo, scale, ["maui", "oahu", "kauai"])
        if min(m.sum() for m in ms.values()) >= HAWAII_MIN_TILES: break
        scale += 0.25
    return scale


def hawaii(land, geo, mid):
    lo0, lo1, la0, la1 = HAWAII_BOX
    if not (_inside(geo, lo0, la1, pad=4) and _inside(geo, lo1, la0, pad=4)): return None
    names = ["hawaii", "maui", "molokai", "lanai", "oahu", "kauai"]
    probe = _island_masks(geo, 1.0, names)
    # real-scale islands already separate (North America): keep the map's islands, add only the missing ones
    lab, _ = ndimage.label(land, structure=FOUR)
    ids = {nm: set(np.unique(lab[probe[nm]]).tolist()) - {0} for nm in names}
    big = ["hawaii", "maui", "oahu", "kauai"]
    separate = all(len(ids[a]) and not (ids[a] & ids[b]) for a in big for b in big if a < b)
    if separate:
        x0, y1 = geo(lo0, la0); x1, y0 = geo(lo1, la1)
        box = np.zeros((H, W), bool); box[int(y0):int(y1) + 1, int(x0):int(x1) + 1] = True
        existing = land & box
        add = {nm: probe[nm] for nm in names if not ids[nm]}
        add = _separate(add, keep=existing)
        newl = np.zeros((H, W), bool)
        for nm, m in add.items():
            if m.sum() >= 6: newl |= m
        return land | newl, newl, np.zeros_like(land)
    # one blob (World): clear the chain and redraw it scaled about its centre
    scale = hawaii_scale(geo)
    ms = _separate(_island_masks(geo, scale, names))
    cx, cy = HAWAII_CENTRE
    cl = [geo(cx + (lo0 - cx) * scale - 0.5, cy + (la1 - cy) * scale + 0.5), geo(cx + (lo1 - cx) * scale + 0.5, cy + (la0 - cy) * scale - 0.5)]
    box = np.zeros((H, W), bool)
    box[max(0, int(min(cl[0][1], geo(lo0, la1)[1]))):int(max(cl[1][1], geo(lo1, la0)[1])) + 1,
        max(0, int(min(cl[0][0], geo(lo0, la1)[0]))):int(max(cl[1][0], geo(lo1, la0)[0])) + 1] = True
    newl = np.zeros((H, W), bool)
    for nm in names:
        if ms[nm].sum() >= 6: newl |= ms[nm]
    out = (land & ~box) | newl
    return out, out & ~land, land & ~out, scale


def island_mag(newl):
    """elevation magnitude (WorldMap 0-30) for redrawn island tiles: coast plains, inland highland, the big
    island's core mountains (Mauna Kea / Mauna Loa)"""
    d = ndimage.distance_transform_cdt(np.pad(newl, 1), metric="taxicab")[1:-1, 1:-1]
    m = np.select([d <= 1, d == 2, d == 3], [3, 8, 13], np.minimum(26, 13 + 4 * (d - 3)))
    return np.where(newl, m, 0).astype(np.uint8)


def apply(land, geo, mid):
    """land: HxW bool. Returns (new land, log list, added-land mask)."""
    log = []
    added = np.zeros_like(land)
    def bbox(m):
        ys, xs = np.nonzero(m)
        return [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())] if len(xs) else None
    for nm in ("suez", "panama"):
        r = carve_canal(land, geo, nm)
        if r is not None:
            land, rem = r
            log.append({"fix": nm, "to_water": int(rem.sum()), "box_x0y0x1y1": bbox(rem)})
    r = open_hainan(land, geo)
    if r is not None:
        land, rem = r
        log.append({"fix": "hainan", "to_water": int(rem.sum()), "box_x0y0x1y1": bbox(rem)})
    r = hawaii(land, geo, mid)
    if r is not None:
        new, add, rem = r[:3]
        e = {"fix": "hawaii", "to_land": int((add & ~land).sum()), "to_water": int(rem.sum()), "box_x0y0x1y1": bbox(add | rem)}
        if len(r) > 3: e["scale"] = r[3]
        land = new; added |= add
        log.append(e)
    return land, log, added


# ---- sim/real_maps.gd (tab 0 maps): python3 tools/mapfix.py ----
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RM_SRC = {"world": "src/shared/Data/Maps/World.luau", "europe": "src/server/MapData/Europe.luau", "asia": "src/server/MapData/Asia.luau",
          "northamerica": "src/server/MapData/NorthAmerica.luau", "southamerica": "src/server/MapData/SouthAmerica.luau",
          "africa": "src/server/MapData/Africa.luau"}


def geo_realmap(mid, src_root):
    """convert_maps2.py placement: crop to the land bbox + 8 (World without rows >= 845), int(w * sc)."""
    if mid in BB: return geo_bbox(mid)
    import zstandard
    s = open(os.path.join(src_root, RM_SRC[mid]), encoding="utf-8").read()
    w = int(re.search(r"width = (\d+)", s).group(1)); h = int(re.search(r"height = (\d+)", s).group(1))
    raw = zstandard.ZstdDecompressor().decompress(base64.b64decode(re.search(r'terrain = "([^"]+)"', s).group(1)), max_output_size=w * h)
    a = np.frombuffer(raw, np.uint8).reshape(h, w)
    land = ((a & 0x80) != 0) & (a != 0x9F)
    if mid == "world": land[845:, :] = False
    rows = np.where(land.any(1))[0]; cols = np.where(land.any(0))[0]
    y0 = max(rows[0] - 8, 0); y1 = min(rows[-1] + 9, h); x0 = max(cols[0] - 8, 0); x1 = min(cols[-1] + 9, w)
    hh, ww = y1 - y0, x1 - x0; sc = min(W / ww, H / hh); nw, nh = int(ww * sc), int(hh * sc)
    ox, oy = (W - nw) // 2, (H - nh) // 2
    def f(lon, lat):
        sx, sy = src_xy(mid, lon, lat)
        return (sx - x0) * nw / ww + ox, (sy - y0) * nh / hh + oy
    return f


def fix_realmaps(path, src_root, dry=False):
    s = open(path, encoding="utf-8").read()
    head, rest = s.split("const MAPS := ", 1)
    maps_json, tail = rest.split("\nconst NATION_COLORS := ", 1)
    maps = json.loads(maps_json)
    report = {}
    for e in maps:
        codes = np.frombuffer(zlib.decompress(base64.b64decode(e["b64"])), np.uint8).reshape(H, W).copy()
        land = codes > 0
        new, log, added = apply(land, geo_realmap(e["id"], src_root), e["id"])
        if not log or (new == land).all():
            if log: report[e["id"]] = {"fixes": log, "changed": False}
            continue
        mag = island_mag(added)
        nc = np.where(new, codes, 0).astype(np.uint8)
        nc[added] = np.where(mag[added] < 10, 1, np.where(mag[added] < 20, 2, 3))
        moved = []
        for n in e["nations"]:
            x, y = int(n[2]), int(n[3])
            if not nc[y, x]:
                yy, xx = np.nonzero(nc)
                k = int(np.argmin((yy - y) ** 2 + (xx - x) ** 2)); n[2], n[3] = int(xx[k]), int(yy[k])
                moved.append([n[0], [x, y], [n[2], n[3]]])
        e["b64"] = base64.b64encode(zlib.compress(nc.tobytes(), 6)).decode()
        e["land"] = int((nc > 0).sum())
        report[e["id"]] = {"fixes": log, "changed": True, "spawns_moved": moved, "land": e["land"]}
    if not dry:
        tmp = path + ".tmp"
        note = "# tools/mapfix.py applied: Suez + Panama canals, Hawaii islands, Hainan strait (re-run is a no-op).\n"
        if note not in head: head = head.replace("extends RefCounted\n", note + "extends RefCounted\n", 1)
        open(tmp, "w", encoding="utf-8").write(head + "const MAPS := " + json.dumps(maps) + "\nconst NATION_COLORS := " + tail)
        os.replace(tmp, path)
    return report


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else "/workspace/roworld_src"
    rep = fix_realmaps(os.path.join(ROOT, "sim", "real_maps.gd"), src, dry="--dry" in sys.argv)
    print(json.dumps(rep, indent=1))
