#!/usr/bin/env python3
"""Prepare grounded edit jobs; assemble generated interaction strips without drawing art.

Run with the bundled workspace Python (Pillow required). Network generation is
deliberately separate; all model instructions live in model_prompt/images_edits.md.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from collections import deque

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "output/pet-interactions"
PETS = ("lulu", "lumei")
ACTIONS = ("poke", "poked", "hug", "peek")
CELL = (192, 208)
DURATIONS = [180, 220, 300, 700, 340, 260]


def section(markdown: str, name: str) -> str:
    match = re.search(
        rf"<!-- interaction:{re.escape(name)} -->\s*(.*?)\s*<!-- /interaction:{re.escape(name)} -->",
        markdown, re.S,
    )
    if not match:
        raise ValueError(f"Missing prompt section: {name}")
    return match[1]


def prepare() -> None:
    markdown = (ROOT / "model_prompt/images_edits.md").read_text()
    template = section(markdown, "template")
    jobs = []
    for pet in PETS:
        directory = ROOT / "Sources/App/Resources/BuiltinPets" / pet
        manifest = json.loads((directory / "pet.json").read_text())
        idle = Image.open(directory / manifest["spritesheetPath"]).convert("RGBA").crop((0, 0, *CELL))
        reference = WORK / "references" / f"{pet}.png"
        reference.parent.mkdir(parents=True, exist_ok=True)
        idle.save(reference)
        for action in ACTIONS:
            title, sequence = section(markdown, f"action:{action}").split("\n", 1)
            prompt = template.format(identity=section(markdown, f"identity:{pet}"),
                                     action_name=title, sequence=sequence)
            prompt_path = ROOT / "model_prompt/pet_interactions" / pet / action / "images_edits.md"
            prompt_path.parent.mkdir(parents=True, exist_ok=True)
            prompt_path.write_text(prompt + "\n")
            jobs.append({"id": f"{pet}-{action}", "reference": str(reference),
                         "prompt": str(prompt_path),
                         "output": str(WORK / "generated" / f"{pet}-{action}.png")})
    (WORK / "jobs.json").write_text(json.dumps(jobs, indent=2) + "\n")
    print(f"Prepared {len(jobs)} grounded jobs: {WORK / 'jobs.json'}")


def remove_blue(image: Image.Image) -> Image.Image:
    """Recover alpha from a flat blue matte; preserve opaque pet interiors."""
    image = image.convert("RGBA")
    if image.getchannel("A").getextrema()[0] == 0:
        # The API can return real alpha. Hidden RGB is irrelevant; preserve
        # its antialiased edge instead of chroma-keying transparent output.
        result = Image.new("RGBA", image.size)
        result.putdata([(r, g, b, a) if a > 8 else (0, 0, 0, 0)
                        for r, g, b, a in image.getdata()])
        return result
    pixels = []
    for r, g, b, a in image.getdata():
        # Only the blue hue is removed; white clothes, pinks and green props stay opaque.
        dominance = b - max(r, g)
        if dominance > 100 and b > 140:
            pixels.append((0, 0, 0, 0))
        elif dominance > 20 and b > 100:
            alpha = max(0, min(255, round(255 * (100 - dominance) / 80)))
            pixels.append((r, g, b, min(a, alpha)))
        else:
            pixels.append((r, g, b, a))
    result = Image.new("RGBA", image.size)
    result.putdata(pixels)
    return result


def remove_detached_specks(image: Image.Image) -> tuple[Image.Image, int]:
    """Discard tiny disconnected generation marks, preserving the actual pet pixels."""
    width, height = image.size
    alpha = image.getchannel("A")
    occupied = bytearray(value > 8 for value in alpha.getdata())
    components = []
    for start in range(len(occupied)):
        if not occupied[start]:
            continue
        occupied[start] = 0
        queue, component = deque([start]), []
        while queue:
            pixel = queue.popleft()
            component.append(pixel)
            x, y = pixel % width, pixel // width
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < width and 0 <= ny < height:
                    neighbor = ny * width + nx
                    if occupied[neighbor]:
                        occupied[neighbor] = 0
                        queue.append(neighbor)
        components.append(component)
    if not components:
        return image, 0
    cutoff = max(20, max(map(len, components)) * 0.008)
    pixels = list(image.getdata())
    removed = 0
    for component in components:
        if len(component) < cutoff:
            removed += len(component)
            for index in component:
                pixels[index] = (0, 0, 0, 0)
    clean = Image.new("RGBA", image.size)
    clean.putdata(pixels)
    return clean, removed


def foot_anchor(image: Image.Image) -> float:
    """Register the feet, leaving intentional head/arm motion intact."""
    top = round(image.height * 0.8)
    alpha = image.getchannel("A").crop((0, top, image.width, image.height))
    weights = list(alpha.getdata())
    total = sum(weights)
    return (sum((i % image.width) * value for i, value in enumerate(weights)) / total
            if total else image.width / 2)


def assemble() -> None:
    report = {"model": "gpt-image-2.6-flare", "endpoint": "images/edits", "pets": {}}
    contact = Image.new("RGB", (6 * 192, 8 * 238), "#20252f")
    draw = ImageDraw.Draw(contact)
    for pi, pet in enumerate(PETS):
        idle = Image.open(WORK / "references" / f"{pet}.png").convert("RGBA")
        idle_box = idle.getbbox()
        if not idle_box:
            raise ValueError(f"Empty idle reference: {pet}")
        target_height = idle_box[3] - idle_box[1]
        target_anchor = idle_box[0] + foot_anchor(idle.crop(idle_box))
        atlas = Image.new("RGBA", (6 * CELL[0], 4 * CELL[1]))
        clips = {}
        pet_report = {}
        for row, action in enumerate(ACTIONS):
            source = WORK / "generated" / f"{pet}-{action}.png"
            strip = remove_blue(Image.open(source))
            crops, boxes, removed_specks = [], [], 0
            for col in range(6):
                left, right = round(col * strip.width / 6), round((col + 1) * strip.width / 6)
                slot, removed = remove_detached_specks(strip.crop((left, 0, right, strip.height)))
                removed_specks += removed
                bbox = slot.getbbox()
                if not bbox or bbox[0] == 0 or bbox[2] == slot.width:
                    raise ValueError(f"Empty or clipped source slot: {pet}-{action}:{col}")
                crops.append(slot.crop(bbox))
                boxes.append(bbox)
            # One scale for the whole action. Avoid frame-by-frame size pumping.
            median_height = sorted(c.height for c in crops)[len(crops) // 2]
            anchors = [foot_anchor(crop) for crop in crops]
            scale = min(target_height / median_height,
                        (target_anchor - 5) / max(anchors),
                        (CELL[0] - target_anchor - 5) / max(crop.width - anchor for crop, anchor in zip(crops, anchors)),
                        (CELL[1] - 10) / max(c.height for c in crops))
            frames = []
            for col, crop in enumerate(crops):
                size = tuple(max(1, round(v * scale)) for v in crop.size)
                resized = crop.resize(size, Image.Resampling.LANCZOS)
                cell = Image.new("RGBA", CELL)
                # Keep the floor and torso registration stable through each gesture.
                x = round(target_anchor - anchors[col] * scale)
                y = idle_box[3] - size[1]
                if x < 3 or y < 3 or x + size[0] > CELL[0] - 3 or y + size[1] > CELL[1] - 3:
                    raise ValueError(f"Final frame would clip: {pet}-{action}:{col}")
                cell.alpha_composite(resized, (x, y))
                atlas.alpha_composite(cell, (col * CELL[0], row * CELL[1]))
                frames.append(cell)
                contact.paste(cell, (col * CELL[0], (pi * 4 + row) * 238 + 24), cell)
            draw.text((8, (pi * 4 + row) * 238 + 5), f"{pet} / {action}", fill="white")
            preview = WORK / "previews" / f"{pet}-{action}.gif"
            preview.parent.mkdir(parents=True, exist_ok=True)
            # GIFs show the transition from the exact original idle and back.
            loop = [idle] + frames + [idle]
            backgrounds = []
            for frame in loop:
                bg = Image.new("RGBA", CELL, "#20252f")
                bg.alpha_composite(frame)
                backgrounds.append(bg.convert("RGB"))
            backgrounds[0].save(preview, save_all=True, append_images=backgrounds[1:],
                                duration=[600] + DURATIONS + [900], loop=0, disposal=2)
            clips[action] = {"row": row, "frameDurationsMS": DURATIONS}
            pet_report[action] = {"source": source.name, "removedDetachedPixels": removed_specks}
        destination = ROOT / "Sources/App/Resources/BuiltinPets" / pet
        atlas.save(destination / "interactions.png")
        (destination / "interactions.json").write_text(json.dumps({
            "version": 1, "spritesheetPath": "interactions.png",
            "cellWidth": CELL[0], "cellHeight": CELL[1], "clips": clips,
        }, indent=2) + "\n")
        report["pets"][pet] = {"actions": list(clips), "cell": CELL, "framesPerAction": 6,
                                "durationMS": sum(DURATIONS), "idleUnchanged": True,
                                "cleanup": pet_report}
    contact.save(WORK / "contact-sheet.png")
    (WORK / "assembly.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Assembled both interaction sheets; review {WORK / 'contact-sheet.png'}")


def review() -> None:
    """Render the actual packaged pixels after the single edge-cleanup pass."""
    contact = Image.new("RGB", (6 * 192, 8 * 238), "#20252f")
    draw = ImageDraw.Draw(contact)
    sheets = {}
    for pi, pet in enumerate(PETS):
        directory = ROOT / "Sources/App/Resources/BuiltinPets" / pet
        atlas = Image.open(directory / "interactions.png").convert("RGBA")
        sheets[pet] = atlas
        idle = Image.open(WORK / "references" / f"{pet}.png").convert("RGBA")
        for row, action in enumerate(ACTIONS):
            frames = [atlas.crop((col * 192, row * 208, (col + 1) * 192, (row + 1) * 208))
                      for col in range(6)]
            for col, cell in enumerate(frames):
                contact.paste(cell, (col * 192, (pi * 4 + row) * 238 + 24), cell)
            draw.text((8, (pi * 4 + row) * 238 + 5), f"{pet} / {action}", fill="white")
            loop = []
            for frame in [idle] + frames + [idle]:
                bg = Image.new("RGBA", CELL, "#20252f")
                bg.alpha_composite(frame)
                loop.append(bg.convert("RGB"))
            loop[0].save(WORK / "previews" / f"{pet}-{action}.gif", save_all=True,
                         append_images=loop[1:], duration=[600] + DURATIONS + [900], loop=0, disposal=2)
    contact.save(WORK / "contact-sheet.png")
    font = ImageFont.truetype("/System/Library/Fonts/Hiragino Sans GB.ttc", 20)
    labels = ("戳戳", "被戳", "抱抱", "探头")
    animation, timings = [], []
    for row, label in enumerate(labels):
        for col in range(6):
            stage = Image.new("RGBA", (420, 278), "#20252f")
            painter = ImageDraw.Draw(stage)
            painter.text((210, 8), label, fill="white", font=font, anchor="mt")
            for pi, pet in enumerate(PETS):
                frame = sheets[pet].crop((col * 192, row * 208, (col + 1) * 192, (row + 1) * 208))
                stage.alpha_composite(frame, (pi * 210 + 9, 32))
                painter.text((pi * 210 + 105, 248), "噜噜" if pet == "lulu" else "噜妹",
                             fill="#c7d1df", font=font, anchor="mt")
            animation.append(stage.convert("RGB"))
            timings.append(DURATIONS[col] + (600 if col == 5 else 0))
    animation[0].save(WORK / "preview.gif", save_all=True, append_images=animation[1:],
                      duration=timings, loop=0, disposal=2)
    print(f"Reviewed deliverables rendered from packaged pixels: {WORK / 'preview.gif'}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "assemble", "review"))
    args = parser.parse_args()
    {"prepare": prepare, "assemble": assemble, "review": review}[args.command]()
