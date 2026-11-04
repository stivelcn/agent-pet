#!/usr/bin/env python3
"""Compose LuMate documentation images from bundled first frames (Pillow required).

No AI generation or source sprite changes. On macOS, uses system fonts for the
optional social preview; PNG crops and the transparent pair are platform-neutral.
Run from any directory: python3 scripts/generate-brand-assets.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "docs/assets"
OUTPUT.mkdir(parents=True, exist_ok=True)
PETS = ROOT / "Sources/App/Resources/BuiltinPets"


def first_frame(name, filename):
    image = Image.open(PETS / name / filename).convert("RGBA")
    frame = image.crop((0, 0, 192, 208))
    assert frame.getbbox(), f"Missing first frame: {name}"
    frame.save(OUTPUT / f"{name}.png", optimize=True)
    return frame


lulu = first_frame("lulu", "spritesheet.webp")
lumei = first_frame("lumei", "spritesheet.png")
pair = Image.new("RGBA", (520, 250))
pair.alpha_composite(lulu, (40, 22))
pair.alpha_composite(lumei, (288, 22))
pair.save(OUTPUT / "lumate-pets.png", optimize=True)

# GitHub recommends 1280 x 640 for a repository social-preview image.
card = Image.new("RGBA", (1280, 640), "#FFF9F0")
draw = ImageDraw.Draw(card)
draw.ellipse((790, -185, 1395, 420), fill="#FFE8CB")
draw.ellipse((880, 370, 1320, 810), fill="#FFEAE5")
draw.rounded_rectangle((744, 124, 1212, 520), 42, fill="#FFFDF8")
fonts = Path("/System/Library/Fonts/Supplemental")
brand = ImageFont.truetype(str(fonts / "Arial Rounded Bold.ttf"), 94)
small = ImageFont.truetype(str(fonts / "Arial Bold.ttf"), 17)
chinese = ImageFont.truetype(str(fonts / "Arial Unicode.ttf"), 30)
name = ImageFont.truetype(str(fonts / "Arial Unicode.ttf"), 49)
labels = ImageFont.truetype(str(fonts / "Arial Unicode.ttf"), 23)
ink, muted = "#49372D", "#907766"
draw.text((88, 135), "A LITTLE COMPANY FOR YOUR CODE", font=small, fill=muted)
draw.text((82, 188), "LuMate", font=brand, fill=ink)
draw.text((90, 300), "噜伴", font=name, fill=ink)
draw.text((90, 397), "你的 AI 助手在忙，", font=chinese, fill=ink)
draw.text((90, 444), "你的桌面有伴。", font=chinese, fill=ink)
draw.text((90, 557), "macOS 14+  /  DESKTOP COMPANION", font=small, fill=muted)
for frame, x, label in [(lulu, 762, "噜噜"), (lumei, 987, "噜妹")]:
    scaled = frame.resize((211, 229), Image.Resampling.LANCZOS)
    card.alpha_composite(scaled, (x, 196))
    bbox = draw.textbbox((0, 0), label, font=labels)
    draw.text((x + (211 - (bbox[2] - bbox[0])) / 2, 456), label, font=labels, fill=muted)
card.convert("RGB").save(OUTPUT / "lumate-social-preview.png", optimize=True)
print(f"Saved four documentation PNGs to {OUTPUT}")
