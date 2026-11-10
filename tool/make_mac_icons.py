"""Build the macOS app icon set from assets/icon-1024.png: a rounded tile with
the standard margin on a transparent canvas.
Run: python3 -I tool/make_mac_icons.py  (needs Pillow)."""
from PIL import Image, ImageDraw

SRC = 'assets/icon-1024.png'
OUT = 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_%d.png'
SIZES = [16, 32, 64, 128, 256, 512, 1024]

def build(px):
    s = 2
    n = 1024 * s
    tile = round(n * 824 / 1024)
    off = (n - tile) // 2
    art = Image.open(SRC).convert('RGBA').resize((tile, tile), Image.LANCZOS)
    mask = Image.new('L', (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (off, off, off + tile, off + tile), radius=round(tile * 0.2237), fill=255)
    canvas = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    canvas.paste(art, (off, off))
    canvas.putalpha(mask)
    return canvas.resize((px, px), Image.LANCZOS)

for px in SIZES:
    build(px).save(OUT % px)
