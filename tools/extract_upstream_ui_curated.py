#!/usr/bin/env python3
"""Curated RoWorld UI tables -> frontline-godot/ui_upstream/*.json (each entry keeps its source file:line).
Usage: python3 tools/extract_upstream_ui_curated.py [/path/to/roworld_src]"""
import json, os, re, sys, collections

SRC = sys.argv[1] if len(sys.argv) > 1 else "/workspace/roworld_src"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "ui_upstream")
GODOT_ASSETS = os.path.join(ROOT, "assets")

def read(rel):
    return open(os.path.join(SRC, rel), encoding="utf-8").read().splitlines()

def table_block(rel, start_pat):
    """Lines (lineno, text) of the Luau table that starts on the line matching start_pat (brace-balanced)."""
    L = read(rel)
    for i, l in enumerate(L):
        if re.search(start_pat, l):
            depth, out = 0, []
            for j in range(i, len(L)):
                code = L[j].split("--", 1)[0]
                depth += code.count("{") - code.count("}")
                out.append((j + 1, L[j]))
                if depth <= 0 and j > i or (depth == 0 and "{" in code and "}" in code):
                    return out
            return out
    raise KeyError(start_pat)

def kv_strings(rel, pat):
    out = {}
    for n, l in table_block(rel, pat)[1:]:
        m = re.match(r'\s*\[?"?([\w]+)"?\]?\s*=\s*"((?:[^"\\]|\\.)*)"', l)
        if m:
            out[m.group(1)] = {"value": m.group(2), "ref": "%s:%d" % (rel, n)}
    return out

def kv_any(rel, pat):
    out = {}
    for n, l in table_block(rel, pat)[1:]:
        m = re.match(r'\s*\[?"?([\w]+)"?\]?\s*=\s*(.+?),?\s*(--.*)?$', l)
        if m:
            out[m.group(1)] = {"value": m.group(2).rstrip(","), "ref": "%s:%d" % (rel, n)}
    return out

def lua_val(v):
    v = v.strip().rstrip(",")
    m = re.match(r"^\{\s*(.*)\s*\}$", v)
    if m:
        inner = m.group(1)
        if "=" in inner:
            d = {}
            for k, x in re.findall(r'(\w+)\s*=\s*("[^"]*"|[-\d.]+)', inner):
                d[k] = x.strip('"') if x.startswith('"') else float(x)
            return d
        return [lua_val(x) for x in re.findall(r'"[^"]*"|[-\d.]+', inner)]
    if v.startswith('"'):
        return v.strip('"')
    try:
        return float(v)
    except ValueError:
        return v

def dump(name, obj):
    json.dump(obj, open(os.path.join(OUT, name), "w"), indent=1, ensure_ascii=False)
    print("wrote", name)

# ---------- theme tokens (UITheme.luau) ----------
UT = "src/client/UI/UITheme.luau"
tokens = {}
for i, l in enumerate(read(UT), 1):
    m = re.match(r"^UITheme\.([A-Z][A-Z0-9_]*) = (.+?)\s*(--.*)?$", l)
    if not m:
        continue
    name, v = m.group(1), m.group(2)
    e = {"ref": "%s:%d" % (UT, i), "src": v}
    mm = re.match(r"UITheme\.rgba\(([-\d.]+), ([-\d.]+), ([-\d.]+)(?:, ([-\d.]+))?\)", v)
    mn = re.match(r"Color3\.new\(([-\d.]+), ([-\d.]+), ([-\d.]+)\)", v)
    mr = re.match(r"Color3\.fromRGB\((\d+), (\d+), (\d+)\)", v)
    if mm or mn:
        g = (mm or mn).groups()
        r, gg, b = (float(x) for x in g[:3])
        e.update(kind="color", hex="#%02x%02x%02x" % tuple(round(x * 255) for x in (r, gg, b)),
                 rgba=[r, gg, b, float(g[3]) if mm and g[3] else 1.0])
    elif mr:
        r, gg, b = (int(x) for x in mr.groups())
        e.update(kind="color", hex="#%02x%02x%02x" % (r, gg, b), rgba=[r / 255, gg / 255, b / 255, 1.0])
    else:
        try:
            e.update(kind="number", value=float(v))
        except ValueError:
            e["kind"] = "other"
    if m.group(3):
        e["comment"] = m.group(3).lstrip("- ")
    tokens[name] = e
theme = {
    "source": UT, "design_size": [1600, 900],
    "ui_scale_rule": "desktop: clamp(min(vw/1600, vh/900), 0.75, 2.5); touch: clamp(.., 1.0, 2.0) (UITheme.luau:1312)",
    "font": {"family": "Rubik", "weights": [100, 200, 300, 400, 500, 600, 700, 800, 900], "roblox_font_id": 12187365977,
             "line_em": 1.185, "ascent_em": 0.935, "tabular_digit_ratio": 0.975, "ref": UT + ":207-270",
             "note": "Rubik is not shipped in the repo (Roblox asset id only)"},
    "tokens": tokens,
    "button_variants": {
        "Button/GlassButton": {"bg": "FILL", "hover": "FILL_2", "pressed": "rgba(1,1,1,0.03)", "border": "LINE", "border_hover": "LINE_2", "font": "TEXT", "weight": 600},
        "PublicButton": {"bg": "CYAN@0.10", "hover": "CYAN@0.18", "pressed": "CYAN@0.06", "border": "CYAN@0.55", "border_hover": "CYAN@0.9", "font": "TEXT", "weight": 600},
        "GhostButton": {"bg": "clear", "hover": "FILL", "pressed": "rgba(1,1,1,0.03)", "border": "clear", "font": "TEXT_2 (hover TEXT)", "weight": 600},
        "DangerButton": {"bg": "RED@0.14", "hover": "RED@0.26", "pressed": "RED@0.08", "border": "RED@0.45", "border_hover": "RED@0.8", "font": "#ffc7cc", "weight": 700},
        "ChipButton": {"bg": "rgba(1,1,1,0.04)", "hover": "FILL_2", "pressed": "AMBER@0.2 border AMBER@0.9", "radius": 999, "pad_h": 14, "font": "TEXT_2 (pressed AMBER_HI)", "weight": 600, "size": 13},
        "PrimaryButton": {"bg": "AMBER", "hover": "AMBER_HI", "pressed": "lerp(AMBER_LO, AMBER, .5)", "radius": "R_MD (10)", "lip_bottom_px": 3, "lip": "AMBER_LO", "pad": [22, 10], "font": "INK", "weight": 800, "spacing": 2, "size": 17},
        "SurrenderButton": {"bg": "SURRENDER_RED", "hover": "SURRENDER_RED_HI", "lip": "SURRENDER_RED_LO", "lip_bottom_px": 3, "font": "white", "weight": 800, "spacing": 2, "size": 17},
        "ref": UT + ":1602-1760",
    },
    "glass_panel": {"tint": "GLASS #0d1326 @0.84 (+GLASS_BOOST 0.08)", "border": "1 px LINE", "sheen": "top gradient GLASS_SHEEN 0.045 + sheen line",
                    "shadow": "9-slice soft shadow (Assets/UIKit.shadows)", "ref": "src/client/UI/GlassPanel.luau:1-40"},
    "message_categories": {
        "0 INFO": {"color": "CYAN", "icon": "info"}, "1 GOOD": {"color": "GREEN", "icon": "crown"},
        "2 BAD": {"color": "ORANGE", "icon": "attack"}, "3 ALERT": {"color": "RED", "icon": "target"},
        "4 ALLIANCE": {"color": "VIOLET", "icon": "alliance"},
        "ref": UT + ":1420-1455; src/shared/Core/Defs.luau:126-130"},
    "owner_ui_color": "luminance < 0.32 -> lerp(col, white, 0.32 - l + 0.1) (UITheme.luau:1457)",
}
dump("theme.json", theme)

# ---------- number formatting ----------
dump("number_format.json", {
    "render_number": {"ref": "src/shared/Core/NumberFormat.luau:12-33", "rule": "floored, never rounded; negatives/NaN -> 0",
        "bands": [[">=1e10", "floor(n/1e8)/10 -> %.1fB"], [">=1e9", "floor(n/1e7)/100 -> %.2fB"], [">=1e7", "%.1fM"],
                  [">=1e6", "%.2fM"], [">=1e5", "floor(n/1000) K (no decimals)"], [">=1e4", "%.1fK"], [">=1e3", "%.2fK"], ["<1e3", "floor(n)"]],
        "examples": {"999": "999", "1234": "1.23K", "24567": "24.5K", "123456": "123K", "1259999": "1.25M", "25000000": "25.0M", "1999999999": "1.99B"}},
    "render_troops": {"ref": "src/shared/Core/NumberFormat.luau:36-38", "rule": "render_number(troops / 10): internal 25,000 reads 2.50K"},
    "fmt_num (gold etc)": {"ref": UT + ":1890-1911", "rule": ">=1e6: %.2fM below 1e7 else %.1fM; >=1e3: %.1fK below 1e5 else %dK; sign kept"},
    "fmt_cost": {"ref": UT + ":1918-1930", "rule": "50K, 125K, 1M, 1.5M, 25M (integer when within 0.05)"},
    "fmt_pct": {"ref": UT + ":1932-1938", "rule": ">=10%: %.1f%%; 0<p<1: %.2f%%; else %.1f%%"},
    "fmt_time": {"ref": UT + ":1940-1946", "rule": "m:ss, h:mm:ss from 3600 s"},
    "fmt_rate": {"ref": UT + ":1948-1953", "rule": "|v|<0.5 -> '±0/s'; else '+'/'−' + fmt_num(|v|) + '/s'"},
    "godot_port": "ui_upstream/number_format.gd",
})

# ---------- audio ----------
AD = "src/client/Audio/AudioDirector.luau"
def block_dict(rel, pat):
    return {k: {"value": lua_val(v["value"]), "ref": v["ref"]} for k, v in kv_any(rel, pat).items()}
def manifest(rel):
    out = {}
    for i, l in enumerate(read(rel), 1):
        m = re.match(r'\s*(\w+) = \{ id = "([^"]+)", length = ([\d.]+) \}', l)
        if m:
            out[m.group(1)] = {"id": m.group(2), "length_s": float(m.group(3)), "ref": "%s:%d" % (rel, i)}
    return out
sfx_names = [re.search(r'"(\w+)"', l).group(1) for _, l in table_block(AD, r"^AudioDirector\.SFX_NAMES = \{")[1:] if re.search(r'"(\w+)"', l)]
audio = {
    "note": "No audio files are in the repo: every sound/music track is a Roblox asset id. Names, lengths and mixing rules below are factual; files must come from elsewhere.",
    "sfx_names": {"list": sfx_names, "ref": AD + ":41"},
    "manifest_audio": manifest("src/shared/Assets/Audio.luau"),
    "manifest_audio_extra": manifest("src/shared/Assets/AudioExtra.luau"),
    "manifest_audio_ui": manifest("src/shared/Assets/AudioUI.luau"),
    "logical_ids": kv_strings("src/client/UI/UICtx.luau", r"^UICtx\.SFX = \{"),
    "logical_fallback": kv_strings("src/client/UI/UICtx.luau", r"^UICtx\.SFX_FALLBACK = \{"),
    "logical_gap_ms": block_dict("src/client/UI/UICtx.luau", r"^UICtx\.SFX_GAP = \{"),
    "cooldowns_ms_fallback": block_dict(AD, r"^AudioDirector\.COOLDOWNS = \{"),
    "throttle_ms": block_dict(AD, r"^AudioDirector\.THROTTLE_MS = \{"),
    "max_same": block_dict(AD, r"^AudioDirector\.MAX_SAME = \{"),
    "priority": block_dict(AD, r"^AudioDirector\.PRIORITY = \{"),
    "auto_duck_db_hold_s": block_dict(AD, r"^AudioDirector\.AUTO_DUCK = \{"),
    "replace": {"attack_launch": "order_ack", "ref": AD + ":821"},
    "trim_db": {"conquer": -6.0, "ref": AD + ":823"},
    "levels": {"music_volume_db": -6.0, "sfx_volume_db": 0.0, "voice_count": 18, "default_throttle_ms": 50, "default_max_same": 3,
               "crossfade_s": 2.0, "track_overlap_s": 2.0, "mood_fade_s": 3.0, "war_fade_s": 2.0, "toggle_fade_s": 0.6,
               "duck_attack_db_per_s": 60.0, "duck_release_db_per_s": 6.0, "ref": AD + ":300-390"},
    "border_pop": {k: v for k, v in [("POP_SLOW", 40.0), ("POP_FAST", 600.0), ("POP_RATE_MIN", 2.0), ("POP_RATE_MAX", 20.0), ("POP_CURVE", 2.0),
                   ("POP_SMOOTH_S", 0.45), ("POP_PER_BATCH", 2), ("POP_PITCH_MIN", 0.8), ("POP_PITCH_MAX", 1.1), ("POP_WARM_S", 15.0),
                   ("POP_COOL_S", 6.0), ("POP_RUN_GAP_S", 0.7), ("POP_JITTER", 0.012), ("POP_PROGRESS_LIFT", 0.05),
                   ("POP_DB_MIN", -9.0), ("POP_DB_MAX", -3.0), ("POP_BIG", 60.0), ("HUSH_POPS", {"eliminate": 0.65}), ("ref", AD + ":260-306")]},
}
st = "src/shared/Assets/Soundtrack.luau"
tracks = {}
for i, l in enumerate(read(st), 1):
    m = re.match(r'\s*(\w+) = \{ id = "([^"]+)", length = ([\d.]+), title = "([^"]+)", pack = "([^"]+)" \}', l)
    if m:
        tracks[m.group(1)] = {"id": m.group(2), "length_s": float(m.group(3)), "title": m.group(4), "pack": m.group(5), "ref": "%s:%d" % (st, i)}
moods = {}
for i, l in enumerate(read(st), 1):
    m = re.match(r"\s*(title|wait|calm|war|victory|defeat) = \{(.*)\},", l)
    if m:
        moods[m.group(1)] = {"tracks": re.findall(r'"(\w+)"', m.group(2)), "ref": "%s:%d" % (st, i)}
audio["soundtrack"] = {"credit": "Music by Rodrigo Flores (Orchestral Ambients), CC BY 4.0", "tracks": tracks, "moods": moods,
                       "mood_rules": "src/client/Audio/MusicMood.luau (war holds WAR_HOLD_S 40 s after the last fight; tribes don't count)",
                       "legacy_themes": {"menu": 106.666667, "war": 160, "ref": "src/shared/Assets/Audio.luau:8-11"}}
# event -> sound routing (UIAdvisor), written by hand from the code, with refs
UA = "src/client/UI/UIAdvisor.luau"
audio["event_routing"] = [
    {"event": "own structure added (built or captured)", "sfx": "build", "who": "only when UIRules.on_structure says old or new owner is me", "ref": UA + ":303-313; src/client/UI/UIRules.luau:339"},
    {"event": "own transport launched", "sfx": "boat -> boat_launch", "who": "only my units (UIRules.on_unit owner == me)", "ref": UA + ":315-327; src/client/UI/UIRules.luau:364"},
    {"event": "own warship launched", "sfx": "warship", "who": "only mine", "ref": UA + ":323-326"},
    {"event": "shell fired", "sfx": "shell_fire", "level_db": "mine -8, others -12 (only when on screen)", "ref": UA + ":334-341"},
    {"event": "air strike / slug fired", "sfx": "sam_launch (pitch .85) / shell_fire (pitch .6)", "level_db": "mine -2, others -8; others only on screen", "ref": UA + ":342-344"},
    {"event": "nuke launched by me (not warheads)", "sfx": "nuke_launch", "ref": UA + ":346-349"},
    {"event": "nuke aimed at my land", "sfx": "alarm -> nuke_alarm", "ref": UA + ":350-353"},
    {"event": "nuke detonated", "sfx": "explosion -> nuke_explosion", "level_db": "mine/at my land 0, others -3; only if on screen or mine", "ref": UA + ":363-399"},
    {"event": "nuke shot down by SAM", "sfx": "(silent: message says it)", "ref": UA + ":385-391"},
    {"event": "shell hit / strike hit", "sfx": "shell_hit (mine -6, others -11, on screen) / intercept -> sam_intercept", "ref": UA + ":376-388"},
    {"event": "attack launched or received", "sfx": "NONE ('more annoying than useful', 2026-09-27); being attacked shows a toast only", "ref": UA + ":599-630"},
    {"event": "alliance request to me", "sfx": "ally_request", "ref": UA + ":632-638"},
    {"event": "alliance formed (me)", "sfx": "alliance", "ref": UA + ":646-666"},
    {"event": "I betrayed / was betrayed", "sfx": "betrayal", "ref": UA + ":667-681"},
    {"event": "naval news (sinkings, trade captures)", "sfx": "NONE (silent since 2026-09-27)", "ref": UA + ":710-726"},
    {"event": "any other Sim message with category ALERT", "sfx": "toast -> ui_tab at -4 dB", "ref": UA + ":722-725"},
    {"event": "I eliminated a nation", "sfx": "eliminate (BedWars kill sound; replaced 'conquer')", "ref": UA + ":777-789; src/client/UI/UICtx.luau:90-93"},
    {"event": "I was eliminated / lost", "sfx": "defeat", "ref": UA + ":806-815, 817-848"},
    {"event": "game over", "sfx": "victory or defeat", "ref": UA + ":817-866"},
    {"event": "my border grows", "sfx": "expand_pop run via AudioDirector.pop (rate/pitch rules in border_pop)", "ref": UA + ":273-301; " + AD + ":901-975"},
    {"event": "spawn placed", "sfx": "spawn -> spawn_confirm", "ref": "src/client/UI/UIInteract.luau:355"},
    {"event": "notice toast (UIRoot.notice)", "sfx": "deny (severity 2) else toast, -4 dB", "ref": "src/client/UI/UIRoot.luau:1918"},
    {"event": "'conquer' sting", "sfx": "not triggered by any client call site in this commit (still in manifest)", "ref": "grep ctx:sfx"},
]
dump("audio.json", audio)

# ---------- icons / atlases ----------
icons = {}
def godot_has(*parts):
    p = os.path.join(GODOT_ASSETS, *parts)
    return "res://assets/" + "/".join(parts) if os.path.exists(p) else None
for rel, group, folder in [("src/shared/Assets/UiIcons.luau", "UiIcons", "ui_icons"),
                           ("src/shared/Assets/ArsenalArt.luau", "ArsenalArt.ui", "arsenal/ui"),
                           ("src/shared/Assets/MapSprites.luau", "MapSprites.ui", "map_sprites/ui")]:
    in_ui = group != "ArsenalArt.ui" and group != "MapSprites.ui"
    section = None
    for i, l in enumerate(read(rel), 1):
        if re.match(r"\s*ui = \{", l):
            section = "ui"; continue
        if re.match(r"\s*renders = \{", l):
            section = "renders"; continue
        m = re.match(r'\s*(\w+) = "(rbxassetid://\d+)"', l)
        if m and (in_ui or section == "ui"):
            k = m.group(1)
            repo_png = "assets/%s/%s.png" % (folder, k)
            e = icons.setdefault(k, {"sources": []})
            e["sources"].append({"group": group, "asset": m.group(2), "ref": "%s:%d" % (rel, i),
                                 "repo_png": repo_png if os.path.exists(os.path.join(SRC, repo_png)) else None})
for k, e in icons.items():
    # UITheme.icon precedence: MapSprites.ui > UiIcons > ArsenalArt.ui (UITheme.luau:1355-1415)
    order = {"MapSprites.ui": 0, "UiIcons": 1, "ArsenalArt.ui": 2}
    e["sources"].sort(key=lambda s: order[s["group"]])
    e["resolved"] = e["sources"][0]["group"]
    e["godot"] = (godot_has("ui", k + ".png") if e["resolved"] == "MapSprites.ui" else None) or godot_has("ui_icons", k + ".png") \
        or godot_has("arsenal", "ui", k + ".png") or godot_has("ui", k + ".png")
usage = collections.defaultdict(list)
for u in json.load(open(os.path.join(OUT, "icon_usage.json"))):
    usage[u["icon"]].append("%s:%d" % (u["file"], u["line"]))
for k in icons:
    icons[k]["used_at"] = usage.get(k, [])
dump("icons.json", {"precedence": "UITheme.icon(): BUILTIN (robux) > crate > MapSprites.ui > UiIcons > ArsenalArt.ui (src/client/UI/UITheme.luau:1355-1415)",
                    "mask_format": "128x128 white-on-transparent, tint at draw time; app_icon full colour 512 (UiIcons.luau:1-5)",
                    "icons": icons, "unused_or_dynamic_keys_used": sorted(set(usage) - set(icons))})
atl = {
    "MapSprites": {"ref": "src/shared/Assets/MapSprites.luau",
        "icons": {"repo_png": "assets/map_sprites/glyphs.png", "cell": 64, "cols": 9, "order": ["city", "port", "factory", "defense", "sam", "silo", "artillery", "airfield", "railgun"]},
        "shapes": {"repo_png": "assets/map_sprites/plates.png", "cell": 112, "cols": 9, "rows": "0 whole shape -> rim colour, 1 inset -> fill colour"},
        "shapes_one": {"repo_png": "assets/map_sprites/plates_one.png", "cell": 112, "cols": 9},
        "shape_scale": [1, 1, 1.12, 1.1, 1.15, 1.3, 1.2, 1.35, 1.25], "icon_fill": [0.78, 0.74, 0.74, 0.74, 0.8, 0.76, 0.82, 0.8, 0.86],
        "units": {"repo_png": "assets/map_sprites/units.png", "cell": 13, "cols": 12, "order": ["transport", "trade", "warship", "atom", "hydrogen", "mirv", "sam", "shell", "warhead", "train", "carriage", "carriage_loaded"], "rows": "0 territory colour, 1 border colour"},
        "units_one": {"repo_png": "assets/map_sprites/units_one.png"},
        "status": {"repo_png": "assets/map_sprites/status.png", "cell": 256, "cols": 3, "pad": 16, "order": ["crown", "traitor", "disconnected", "alliance", "allianceRequest", "target", "embargo", "nukeRed", "nukeWhite", "allianceFaded", "doomsdayClock", "verified"]},
        "godot": {"plates": "res://assets/plates.png", "glyphs": "res://assets/glyphs.png", "units": "res://assets/units.png", "status": "res://assets/status.png"}},
    "UiShapes": {"ref": "src/shared/Assets/UiShapes.luau", "note": "radial-menu annular-sector masks, 5 pages; px=2, gap_deg=2.2; variants desk ri44/ro116, desk_hov ro122, touch ri50/ro128, touch_hov ro134; repo PNGs in assets/ui_shapes/",
        "segments": {k: lua_val(v["value"]) for k, v in kv_any("src/shared/Assets/UiShapes.luau", r"^\s*segments = \{").items()}},
    "UIKit": {"ref": "src/shared/Assets/UIKit.luau", "note": "15 soft-shadow 9-slices (feather 40, radius 8..120) and BusyChip spinner arc/ring; Roblox ids only"},
    "MapFx": {"ref": "src/shared/Assets/MapFx.luau", "repo_png": "assets/map_fx/map_fx.png", "godot": "res://assets/map_fx/map_fx.png"},
    "Rails": {"ref": "src/shared/Assets/RailArt.luau", "repo_png": "assets/rails/{h,v,tl,tr,bl,br}.png", "godot": "res://assets/rails/"},
    "Flags": {"ref": "src/shared/Assets/Flags.luau", "repo": "assets/flags/*.svg (+ names.json), SVG only", "note": "not in the Godot project; flag code per nation in maps/upstream/*.json"},
}
for k in ("MapFx.luau", "RailArt.luau"):
    pass
dump("atlases.json", atl)

# ---------- strings ----------
UR = "src/client/UI/UIRules.luau"
cat = {"build_kinds": ["city", "port", "factory", "defense", "sam", "silo", "warship"], "nuke_kinds": ["atom", "hydrogen", "mirv"],
       "hotkey_actions": {"order": ["city", "port", "factory", "defense", "sam", "silo", "warship", "atom", "hydrogen", "mirv"], "keys": ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], "ref": UR + ":39-40"},
       "arsenal": {"build": ["artillery", "airfield", "railgun"], "nukes": ["mega", "scatter", "airstrike", "slug"], "all": ["artillery", "airfield", "railgun", "mega", "scatter", "airstrike", "slug", "reinforce"], "ref": UR + ":44-46"},
       "titles": kv_strings(UR, r"^UIRules\.TITLES = \{"), "short": kv_strings(UR, r"^UIRules\.SHORT = \{"),
       "blurbs": kv_strings(UR, r"^UIRules\.BLURBS = \{"), "place_reasons": kv_strings(UR, r"^UIRules\.PLACE_REASONS = \{"),
       "upgradable": ["city", "port", "factory", "sam", "silo"], "bulk_steps": {"structure": [5, 10], "nuke": [2, 5], "max": 50, "ref": UR + ":651-660"},
       "ratio_stops": {"value": [0.10, 0.25, 0.35, 0.50, 0.75], "default": 0.25, "ref": "src/client/UI/UICtx.luau:52-55"}}
dump("catalog.json", cat)
hot = {"ref": "src/client/UI/UIInteract.luau:1640-1690; src/client/Main.luau (M, Home)", "keys": {
    "Esc / X": "cancel (escape)", "H": "toggle help", "Tab": "toggle leaderboard (not on title)", "Space": "primary action at hover (play/spawn)",
    "Backspace": "retreat latest attack", "Q / E": "attack ratio -/+ one stop (repeats while held)", "Shift+Wheel": "attack ratio",
    "1..9, 0": "select build/nuke action (UIRules.ACTIONS order)", "M": "music toggle (Main)", "Home": "focus your nation (Main)"}}
dump("hotkeys.json", hot)
allstr = json.load(open(os.path.join(OUT, "strings_all.json")))
by = collections.defaultdict(list)
for s in allstr:
    if "/Dev/" in s["file"]:
        continue
    by[os.path.basename(s["file"]).replace(".luau", "")].append({"line": s["line"], "text": s["text"]})
dump("strings_by_screen.json", {"note": "user-facing-looking string literals per client module (heuristic filter; file:line)", "files": by})
dump("map_palette.json", {"ref": "src/client/Map/MapSurface.luau:50-56,111,193-198; tools/assets/make_map_thumbs.py:40-75",
    "terrain": {"ocean": "#4785b5", "sand_shore": "#cccb9e", "plains": "#bedc8a", "highland": "#dccb9e", "mountain": "#e6e6e6", "background_impassable": "#3c3c3c"},
    "ramps": {"plains": "G - 2*mag (mag 0-9)", "highland": "+2*(mag-10) each channel", "mountain": "+mag//2 each channel", "shore_water": "0.7*ocean + 76.5", "water": "ocean - min(mag,10)"},
    "territory": {"alpha": 150, "saturation": 0.85, "border_darken": 0.125, "highlight_brighten": 0.25, "friendly_tint": 0.35, "defense_checker_darken": 0.7, "defense_fill_darken": 0.85}})

# ---------- theme_tokens.gd ----------
L = ["# GENERATED by tools/extract_upstream_ui_curated.py from ui_upstream/theme.json (RoWorld src/client/UI/UITheme.luau).",
     "# Reference palette; the live UI keeps its own rounded style.", "extends RefCounted", ""]
for k, v in theme["tokens"].items():
    ln = v["ref"].split(":")[-1]
    if v["kind"] == "color":
        r, g, b, a = v["rgba"]
        L.append("const %s := Color(%.4f, %.4f, %.4f, %.3f)  # %s line %s" % (k, r, g, b, a, v["hex"], ln))
    elif v["kind"] == "number":
        val = int(v["value"]) if float(v["value"]).is_integer() else v["value"]
        L.append("const %s := %s  # line %s" % (k, val, ln))
open(os.path.join(OUT, "theme_tokens.gd"), "w").write("\n".join(L) + "\n")
print("wrote theme_tokens.gd")
