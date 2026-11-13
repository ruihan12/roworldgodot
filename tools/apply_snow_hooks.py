#!/usr/bin/env python3
"""Apply the Antarctica/snow hook (docs/HOOKS.md section "Snow") to a main.gd that already has the
upstream-maps hook (docs/hooks_main.patch). Usage: apply_snow_hooks.py path/to/main.gd
Code 4 = snow: gameplay identical to plains (mtn 0), drawn snow-white. Idempotent."""
import sys
p = sys.argv[1]; s = open(p).read()
if "SNOW_COL" in s: print("already applied"); sys.exit(0)
E = [
 ("var real_nations := []\n",
  "var real_nations := []\n"
  "var snow_src := PackedByteArray()  # current map codes; 4 = snow (Antarctica): plains rules, white colour\n"
  "const SNOW_COL := Color8(0xF4, 0xF7, 0xFA)\n"),
 ("\tif map_tab == 2: return UpstreamMaps.real_map_at(k)\n",
  "\tif map_tab == 2: return UpstreamMaps.real_map_at(k)\n"
  "\tif map_tab == 0 and k == 0: return UpstreamMaps.as_real_map(\"world\")  # World with Antarctica + 3 aq spawns\n"),
 ("\tvar rmap := _real_map(map_i) if map_tab != 1 else {}\n",
  "\tvar rmap := _real_map(map_i) if map_tab != 1 else {}\n"
  "\tsnow_src = raw_bytes\n"),
 ("\t\t\t\tif code >= 3:\n\t\t\t\t\tmtn[i] = 2; elev[i] = 0.50 + jitter\n",
  "\t\t\t\tif code == 4:  # snow: exactly plains for movement/conquest/spawns/building\n"
  "\t\t\t\t\tmtn[i] = 0; elev[i] = 0.10 + jitter\n"
  "\t\t\t\telif code >= 3:\n\t\t\t\t\tmtn[i] = 2; elev[i] = 0.50 + jitter\n"),
 ("\t\t\tbc[i] = shore_w if shore else ocean[mini(maxi(cdist[i] - 1, 0), 10)]\n\t\telif shore: bc[i] = sand\n",
  "\t\t\tbc[i] = shore_w if shore else ocean[mini(maxi(cdist[i] - 1, 0), 10)]\n"
  "\t\telif snow_src.size() == N and snow_src[i] == 4: bc[i] = SNOW_COL\n"
  "\t\telif shore: bc[i] = sand\n"),
 ("\tif shore: return Color8(0xCC, 0xCB, 0x9E)\n\tvar e: float = elev_map[i]",
  "\tif snow_src.size() == W * H and snow_src[i] == 4: return SNOW_COL\n"
  "\tif shore: return Color8(0xCC, 0xCB, 0x9E)\n\tvar e: float = elev_map[i]"),
 ("\t\tif qual_i >= 2: c = _rw_terrain(i)\n",
  "\t\tif qual_i >= 2: c = _rw_terrain(i)\n"
  "\t\telif owner_map[i] != WATER and snow_src.size() == W * H and snow_src[i] == 4: c = SNOW_COL\n"),
 ("[clampi(mtn[t], 0, 2)]\n",
  "[clampi(mtn[t], 0, 2)]\n"
  "\tif snow_src.size() == W * H and snow_src[t] == 4: terrain = \"Snow (plains rules: loss 80, cost 16.5)\"\n"),
]
for a, b in E:
    n = s.count(a)
    if n != 1: sys.exit("anchor count %d: %r" % (n, a[:70]))
    s = s.replace(a, b)
open(p, "w").write(s); print("snow hook applied: %d edits" % len(E))
