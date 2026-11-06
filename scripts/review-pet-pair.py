#!/usr/bin/env python3
"""Compose previews from actual offscreen app frames and actual Chinese replay bubbles."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
QA = ROOT / 'output/pet-pair/qa'
OUT = ROOT / 'output/pet-pair'
FONT = '/System/Library/Fonts/Hiragino Sans GB.ttc'
heading = ImageFont.truetype(FONT, 24)
caption = ImageFont.truetype(FONT, 16)
combined, combined_times = [], []
for action, label in [('hug', '抱抱'), ('poke', '戳戳'), ('peek', '探头')]:
    bubble = Image.open(QA / f'replay-bubble-{action}.png').convert('RGBA')
    bubble.thumbnail((324, 60), Image.Resampling.LANCZOS)
    frames, times = [], []
    for i in range(37):
        scene = Image.open(QA / f'lulu-{action}-left/{i:02d}.png').convert('RGBA')
        scene = scene.resize((612, 180), Image.Resampling.LANCZOS)
        canvas = Image.new('RGBA', (640, 350), '#1b202a')
        draw = ImageDraw.Draw(canvas)
        draw.text((320, 18), f'双宠互动 · {label}', anchor='mt', font=heading, fill='#fff1cf')
        draw.text((320, 55), '收到时自动播放一次 · 点击气泡可反复回放', anchor='mt', font=caption, fill='#bac6d7')
        canvas.alpha_composite(bubble, ((640-bubble.width)//2, 88))
        canvas.alpha_composite(scene, (14, 148))
        frames.append(canvas.convert('RGB'))
        times.append(100 if i not in (0,36) else 500 if i == 0 else 1200)
    frames[0].save(OUT / f'{label}预览.gif', save_all=True, append_images=frames[1:],
                   duration=times, loop=0, disposal=2, optimize=True)
    combined += frames
    combined_times += times
combined[0].save(OUT / '双宠互动预览.gif', save_all=True, append_images=combined[1:],
                 duration=combined_times, loop=0, disposal=2, optimize=True)
combined[17].save(OUT / '抱抱接触画面.png')
print(OUT / '双宠互动预览.gif')
