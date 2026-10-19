"""
make_fixture_images.py
Generates deterministic solid-colour fixture images with bold label text using Pillow.
"""
import os
from PIL import Image, ImageDraw, ImageFont

OUT_DIR = os.path.join(os.path.dirname(__file__), 'fixtures', 'public', 'parity-images')
os.makedirs(OUT_DIR, exist_ok=True)

IMAGES = [
    ('before_1.jpg', (400, 300), (70, 130, 180), 'BEFORE 1'),
    ('after_1.jpg', (400, 300), (60, 179, 113), 'AFTER 1'),
    ('portrait_1.jpg', (300, 400), (218, 112, 214), 'PORTRAIT 1'),
    ('evidence_1.jpg', (400, 300), (244, 164, 96), 'EVIDENCE 1'),
    ('before_2.jpg', (400, 300), (95, 158, 160), 'BEFORE 2'),
    ('after_2.jpg', (400, 300), (143, 188, 143), 'AFTER 2'),
    ('wide_1.jpg', (800, 300), (100, 149, 237), 'WIDE 1'),
]

for name, (w, h), bg_color, label in IMAGES:
    img = Image.new('RGB', (w, h), color=bg_color)
    draw = ImageDraw.Draw(img)
    # Draw border
    draw.rectangle([(2, 2), (w - 3, h - 3)], outline=(255, 255, 255), width=3)
    # Simple centered text
    # Pillow default font is small, let's draw repeated text or load default
    font = ImageFont.load_default()
    # Draw text roughly centered
    bbox = draw.textbbox((0, 0), label, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    # Draw scale-up pattern or text
    x = (w - tw) // 2
    y = (h - th) // 2
    draw.text((x, y), label, fill=(255, 255, 255), font=font)
    out_path = os.path.join(OUT_DIR, name)
    img.save(out_path, 'JPEG', quality=85)
    print(f'Wrote {out_path} ({w}x{h})')

print('All fixture images generated.')
