#!/usr/bin/env python3
"""Mechanical extraction of RoWorld client UI facts (file:line refs) into frontline-godot/ui_upstream/*.json.
Usage: python3 tools/extract_upstream_ui.py [/path/to/roworld_src]"""
import json, os, re, sys, collections

SRC = sys.argv[1] if len(sys.argv) > 1 else "/workspace/roworld_src"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "ui_upstream")
os.makedirs(OUT, exist_ok=True)
SCAN = ["src/client", "src/shared/Assets", "src/shared/Core/NumberFormat.luau", "src/shared/Core/SimColors.luau",
        "src/shared/Core/Defs.luau", "src/shared/Data"]

def files():
    for s in SCAN:
        p = os.path.join(SRC, s)
        if os.path.isfile(p):
            yield s
        else:
            for dp, _, fs in os.walk(p):
                for f in sorted(fs):
                    if f.endswith(".luau") and "/Maps" not in dp:
                        yield os.path.relpath(os.path.join(dp, f), SRC)

def hexc(r, g, b):
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(v)))) for v in (r, g, b))

NUM = r"\s*(-?[\d.]+)\s*"
RE_NEW = re.compile(r"Color3\.new\(" + NUM + "," + NUM + "," + NUM + r"\)")
RE_RGB = re.compile(r"Color3\.fromRGB\(" + NUM + "," + NUM + "," + NUM + r"\)")
RE_HEX = re.compile(r'Color3\.fromHex\(\s*"#?([0-9a-fA-F]{6})"\s*\)')
RE_RGBA = re.compile(r"(?:UITheme|T\(\)|T)\.rgba\(" + NUM + "," + NUM + "," + NUM + r"(?:," + NUM + r")?\)")
RE_HEXSTR = re.compile(r'"(#[0-9a-fA-F]{6})"')
RE_ASSIGN = re.compile(r"^\s*(?:local\s+)?([A-Za-z_][\w.]*)\s*=\s*")
RE_KEY = re.compile(r"^\s*\[?\"?([A-Za-z_]\w*)\"?\]?\s*=\s*")
RE_STR = re.compile(r'"((?:[^"\\]|\\.)*)"')
RE_SFX = re.compile(r'(?:ctx:sfx|self\.ctx:sfx|UICtx\.sfx|play_sfx|ctx\.sfx)\(\s*(?:self\s*,\s*)?(?:if [^,]*? then )?"([a-z_0-9]+)"(.*)$')
RE_ICON = re.compile(r'(?:icon|icon_rect|icon_name|glyph)\s*(?:\(|=)\s*"([a-z_0-9]+)"')
RE_CONST = re.compile(r"^(?:local\s+)?([A-Z][A-Za-z]*\.)?([A-Z][A-Z0-9_]{2,})\s*=\s*(.+?)\s*(--.*)?$")
RE_HEADER = re.compile(r"^--+!?")

colors, strings, sfx, icons, consts, headers = [], [], [], [], [], {}
for rel in files():
    lines = open(os.path.join(SRC, rel), encoding="utf-8").read().splitlines()
    hdr = []
    for l in lines:
        if l.startswith("--!"):
            continue
        if l.startswith("--"):
            hdr.append(re.sub(r"^--+ ?", "", l))
        elif hdr or l.strip():
            break
    headers[rel] = {"lines": len(lines), "header": "\n".join(hdr).strip()}
    for i, l in enumerate(lines, 1):
        code = l.split("--", 1)[0] if not l.lstrip().startswith("--") else ""
        if not code.strip():
            continue
        m = RE_ASSIGN.match(code) or RE_KEY.match(code)
        name = m.group(1) if m else None
        for rx, kind in ((RE_NEW, "new"), (RE_RGB, "rgb"), (RE_HEX, "hex"), (RE_RGBA, "rgba")):
            for mm in rx.finditer(code):
                if kind == "hex":
                    h, a = "#" + mm.group(1).lower(), 1.0
                elif kind == "rgb":
                    h, a = hexc(*map(float, mm.groups()[:3])), 1.0
                else:
                    v = [float(x) for x in mm.groups()[:3]]
                    h = hexc(*(x * 255 for x in v))
                    a = float(mm.group(4)) if kind == "rgba" and mm.group(4) else 1.0
                colors.append({"file": rel, "line": i, "name": name, "hex": h, "alpha": a, "src": l.strip()[:160]})
        if "/Data/" in rel or "Assets" in rel:
            for mm in RE_HEXSTR.finditer(code):
                colors.append({"file": rel, "line": i, "name": name, "hex": mm.group(1).lower(), "alpha": 1.0, "src": l.strip()[:160]})
        for mm in RE_SFX.finditer(code):
            vol = re.match(r"\s*,\s*([^,)]+)", mm.group(2) or "")
            sfx.append({"file": rel, "line": i, "id": mm.group(1), "args": (mm.group(2) or "").strip()[:80], "src": l.strip()[:160]})
        for mm in RE_ICON.finditer(code):
            icons.append({"file": rel, "line": i, "icon": mm.group(1)})
        if rel.startswith("src/client"):
            for mm in RE_STR.finditer(code):
                s = mm.group(1)
                if (re.search(r"[A-Za-z]{2}", s) and (" " in s or re.search(r"[A-Z]{2}", s) or re.match(r"^[A-Z][a-z]+", s))
                        and not s.startswith(("rbxasset", "Enum", "http")) and not re.match(r"^[A-Z][a-zA-Z]+$", s)
                        and "%s" not in s[:0]):
                    strings.append({"file": rel, "line": i, "text": s, "ctx": code.strip()[:140]})
        m = RE_CONST.match(code.strip())
        if m and rel.startswith(("src/client", "src/shared/Core/NumberFormat")):
            consts.append({"file": rel, "line": i, "name": (m.group(1) or "") + m.group(2), "value": m.group(3)[:160],
                           "comment": (m.group(4) or "").lstrip("- ")[:160]})

def dump(name, obj):
    json.dump(obj, open(os.path.join(OUT, name), "w"), indent=1, ensure_ascii=False)

dump("colors_all.json", colors)
dump("strings_all.json", strings)
dump("sfx_callsites.json", sfx)
dump("icon_usage.json", icons)
dump("constants_all.json", consts)
dump("module_headers.json", headers)
cnt = collections.Counter(s["id"] for s in sfx)
print("files", len(headers), "colors", len(colors), "strings", len(strings), "sfx", len(sfx), "icons", len(icons), "consts", len(consts))
print(cnt.most_common(60))
