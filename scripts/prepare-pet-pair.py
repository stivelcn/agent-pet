#!/usr/bin/env python3
"""Register AI-generated, Vision-matted poses to the existing pet's floor and scale."""
from pathlib import Path
import importlib.util
import json
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('old', ROOT / 'scripts/prepare-pet-interactions.py')
old = importlib.util.module_from_spec(spec)
spec.loader.exec_module(old)
report = {}
for pet in ('lulu', 'lumei'):
    directory = ROOT / 'Sources/App/Resources/BuiltinPets' / pet
    manifest = json.loads((directory / 'pet.json').read_text())
    idle = Image.open(directory / manifest['spritesheetPath']).convert('RGBA').crop((0, 0, 192, 208))
    box = idle.getbbox()
    factor = 256 / max(idle.size)
    target_height = (box[3] - box[1]) * factor
    target_bottom = (256 - idle.height * factor) / 2 + box[3] * factor
    target_anchor = (256 - idle.width * factor) / 2 + (box[0] + old.foot_anchor(idle.crop(box))) * factor
    frames = []
    for row in range(4):
        for col in range(6):
            image = Image.open(ROOT / f'output/pet-pair/cutouts/{pet}/{row}-{col}.png').convert('RGBA')
            # Remove near-transparent Vision matte residue; retain antialiased edges.
            image.putalpha(image.getchannel('A').point(lambda value: value if value >= 12 else 0))
            image, _ = old.remove_detached_specks(image)
            bbox = image.getbbox()
            if not bbox or bbox[0] == 0 or bbox[2] == image.width:
                raise ValueError(f'轮廓被裁切：{pet}/{row}-{col}')
            frames.append(image.crop(bbox))
    heights = sorted(frame.height for frame in frames)
    anchors = [old.foot_anchor(frame) for frame in frames]
    scale = min(target_height / heights[len(heights)//2],
                (target_anchor - 4) / max(anchors),
                (256 - target_anchor - 4) / max(frame.width-a for frame,a in zip(frames,anchors)),
                (target_bottom - 4) / max(frame.height for frame in frames))
    atlas = Image.new('RGBA', (1536, 1024))
    for i,(frame,anchor) in enumerate(zip(frames,anchors)):
        frame = frame.resize((round(frame.width*scale), round(frame.height*scale)), Image.Resampling.LANCZOS)
        x,y = round(target_anchor-anchor*scale), round(target_bottom-frame.height)
        atlas.alpha_composite(frame, ((i%6)*256+x, (i//6)*256+y))
    atlas.save(ROOT / f'Sources/App/Resources/BuiltinPets/{pet}/pair-interactions.png', optimize=True)
    report[pet] = {'scale': scale, 'floor': target_bottom, 'bodyAnchor': target_anchor,
                   'frames': 24, 'source': f'outputs/pet-pair/{pet}-poses.png',
                   'model': 'gpt-image-2.6-flare', 'backgroundRemoval': 'macOS Vision'}
(ROOT / 'output/pet-pair/assembly.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
print(json.dumps(report, ensure_ascii=False))
