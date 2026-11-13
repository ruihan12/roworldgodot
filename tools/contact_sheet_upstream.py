#!/usr/bin/env python3
"""Clean contact sheet of the full upstream previews (terrain only, no captions): 4x2 grid."""
import os, sys
from PIL import Image
D = os.environ.get("PREVIEW_FULL", "/workspace/shots/upstream_maps/previews_full")
ORDER = ["world", "europe", "asia", "northamerica", "southamerica", "africa", "pangaea", "onion"]
tw, th, gap = 448, 400, 6
sheet = Image.new("RGB", (4 * tw + 5 * gap, 2 * th + 3 * gap), (24, 28, 36))
for k, mid in enumerate(ORDER):
    im = Image.open(os.path.join(D, mid + ".png")).convert("RGB").resize((tw, th), Image.LANCZOS)
    sheet.paste(im, (gap + (k % 4) * (tw + gap), gap + (k // 4) * (th + gap)))
out = sys.argv[1] if len(sys.argv) > 1 else "/workspace/shots/upstream_maps/contact_sheet.png"
sheet.save(out); print(out)
