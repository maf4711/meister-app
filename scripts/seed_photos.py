#!/usr/bin/env python3
"""Generate test photos + videos for the Meister iOS simulator.

Creates a mix of:
  - unique photos
  - exact duplicates (same bytes)
  - near-duplicates (same content + slight noise)
  - blurry photos (gaussian blur)
  - screenshots (iPhone frame dimensions)
  - large videos (>100 MB target) and a screen recording

Run: python3 seed_photos.py ./fixtures
Then: xcrun simctl addmedia <udid> ./fixtures/*
"""

from __future__ import annotations
import argparse
import math
import random
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

random.seed(42)


def gradient(size, a, b):
    """Smooth two-color diagonal gradient."""
    w, h = size
    base = Image.new("RGB", size, a)
    top = Image.new("RGB", size, b)
    mask = Image.new("L", size)
    for y in range(h):
        for x in range(w):
            t = (x + y) / (w + h)
            mask.putpixel((x, y), int(255 * t))
    base.paste(top, (0, 0), mask)
    return base


def circles(size, count=8, seed=0):
    """Random colorful circles — used for varied content."""
    r = random.Random(seed)
    img = gradient(size, (20, 40, 80), (220, 210, 180))
    draw = ImageDraw.Draw(img, "RGBA")
    for _ in range(count):
        x = r.randint(0, size[0])
        y = r.randint(0, size[1])
        rad = r.randint(30, 200)
        color = (
            r.randint(50, 255),
            r.randint(50, 255),
            r.randint(50, 255),
            r.randint(120, 220),
        )
        draw.ellipse((x - rad, y - rad, x + rad, y + rad), fill=color)
    return img


def add_noise(img, amount=4):
    return Image.eval(
        img, lambda v: max(0, min(255, v + random.randint(-amount, amount)))
    )


def make_screenshot(size=(1179, 2556), label="Meister Screenshot"):
    """Realistic iPhone screenshot dimensions."""
    img = Image.new("RGB", size, (30, 30, 34))
    draw = ImageDraw.Draw(img)
    # Status bar
    draw.rectangle((0, 0, size[0], 110), fill=(15, 15, 18))
    # Content blocks
    for i in range(8):
        y = 200 + i * 260
        draw.rounded_rectangle(
            (40, y, size[0] - 40, y + 220), radius=24, fill=(48, 48, 54)
        )
        draw.rectangle((70, y + 40, 500, y + 80), fill=(220, 220, 220))
        draw.rectangle((70, y + 110, 900, y + 140), fill=(140, 140, 140))
    draw.text((60, 150), label, fill=(240, 240, 240))
    return img


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path, help="Output directory")
    args = parser.parse_args()
    out: Path = args.output
    out.mkdir(parents=True, exist_ok=True)

    print(f"Generating fixtures in {out}/")

    # 1. Ten unique photos
    for i in range(10):
        img = circles((2048, 2048), count=12, seed=i)
        img.save(out / f"unique_{i:02d}.jpg", quality=88)

    # 2. Three exact duplicates of unique_00
    base = out / "unique_00.jpg"
    for i in range(3):
        (out / f"dup_exact_{i}.jpg").write_bytes(base.read_bytes())

    # 3. Near-duplicates (same content + noise) — pHash should still match
    base_img = Image.open(base)
    for i in range(4):
        variant = add_noise(base_img, amount=6)
        variant.save(out / f"dup_near_{i}.jpg", quality=82)

    # 4. Five blurry photos
    for i in range(5):
        img = circles((2048, 2048), count=10, seed=100 + i)
        img = img.filter(ImageFilter.GaussianBlur(radius=14))
        img.save(out / f"blur_{i:02d}.jpg", quality=80)

    # 5. Six screenshots (iPhone resolution)
    for i in range(6):
        img = make_screenshot(label=f"Screenshot #{i + 1}")
        img.save(out / f"screenshot_{i:02d}.png")

    # 6. Large video: 1 MP4 of 20 MB-ish (not full 100 MB to keep it quick)
    large_video = out / "largevideo_0.mp4"
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-f",
            "lavfi",
            "-i",
            "testsrc2=duration=8:size=1920x1080:rate=30",
            "-c:v",
            "libx264",
            "-preset",
            "ultrafast",
            "-b:v",
            "8M",
            "-pix_fmt",
            "yuv420p",
            str(large_video),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    # 7. Screen recording — must start with "RPReplay" per iOS convention
    screen_rec = out / "RPReplay_Final_20260419_031500.mp4"
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-f",
            "lavfi",
            "-i",
            "testsrc2=duration=4:size=1179x2556:rate=30",
            "-c:v",
            "libx264",
            "-preset",
            "ultrafast",
            "-pix_fmt",
            "yuv420p",
            str(screen_rec),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    # Summary
    total = sum(p.stat().st_size for p in out.iterdir() if p.is_file())
    count = sum(1 for _ in out.iterdir() if _.is_file())
    print(f"Generated {count} fixture files ({total // (1024 * 1024)} MB).")


if __name__ == "__main__":
    main()
