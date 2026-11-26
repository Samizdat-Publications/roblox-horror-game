"""Tile every preview in art/previews into art/previews/contact-sheet.png with names."""

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ART = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1]) if len(sys.argv) > 1 else ART / "previews" / "contact-sheet.png"
manifest = json.loads((ART / "models" / "manifest.json").read_text())
names = list(manifest)
cols = 6
tile = 300
rows = (len(names) + cols - 1) // cols
sheet = Image.new("RGB", (cols * tile, rows * (tile + 44)), (245, 245, 240))
draw = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 17)
    small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
except OSError:
    font = small = ImageFont.load_default()
for i, n in enumerate(names):
    im = Image.open(ART / "previews" / f"{n}.png").convert("RGB").resize((tile, tile), Image.LANCZOS)
    x, y = (i % cols) * tile, (i // cols) * (tile + 44)
    sheet.paste(im, (x, y))
    e = manifest[n]
    draw.text((x + 8, y + tile + 2), n, fill=(30, 30, 30), font=font)
    s = e["studs"]
    draw.text((x + 8, y + tile + 23), f"{s[0]} x {s[1]} x {s[2]} studs, {e['triangles']} tris", fill=(80, 80, 80), font=small)
sheet.quantize(colors=256, method=Image.Quantize.MEDIANCUT).save(out, optimize=True)
print("wrote", out, sheet.size)
