"""Render the Fluo launcher icon (stacked F L / U O, Lexend 800, lime on dark).
Run: python3 -I tool/make_icons.py  (needs Pillow)."""
from PIL import Image, ImageDraw, ImageFont

LIME, BG = (200, 255, 61), (9, 9, 11)
FONT = 'assets/fonts/Lexend.ttf'
SIZES = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}

def render(px):
    s = 4  # supersample
    n = px * s
    img = Image.new('RGBA', (n, n), BG + (255,))
    f = ImageFont.truetype(FONT, int(n * 0.375))
    f.set_variation_by_axes([800])
    d = ImageDraw.Draw(img)
    cell = n * 0.30
    cx, cy = n / 2, n / 2
    for i, ch in enumerate('FLUO'):
        x = cx + (-0.5 if i % 2 == 0 else 0.5) * cell
        y = cy + (-0.5 if i < 2 else 0.5) * cell * 1.02
        d.text((x, y), ch, font=f, fill=LIME, anchor='mm')
    return img.resize((px, px), Image.LANCZOS)

for k, px in SIZES.items():
    render(px).save(f'android/app/src/main/res/mipmap-{k}/ic_launcher.png')
render(1024).save('assets/icon-1024.png')
