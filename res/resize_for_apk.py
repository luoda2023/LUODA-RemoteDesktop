#!/usr/bin/env python3
"""
Create transparent LDesk icons for Android mipmap directories.
Run this BEFORE the Flutter build step in CI.

Usage: python3 res/resize_for_apk.py
"""
import sys
import os
from PIL import Image

# Resize targets: density -> (size, dir_name)
MIPMAP_SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    # Go up to repo root
    repo_root = os.path.dirname(base_dir)  # res/ -> repo root
    apk_res = os.path.join(repo_root, "flutter", "android", "app", "src", "main", "res")

    src_path = os.path.join(base_dir, "mac-icon.png")
    dst_dir = apk_res

    if not os.path.exists(src_path):
        print(f"ERROR: Source not found: {src_path}")
        sys.exit(1)

    try:
        src = Image.open(src_path).convert("RGBA")
        src_w, src_h = src.size
        print(f"Source: {src_path} ({src_w}x{src_h})")
    except Exception as e:
        print(f"ERROR: Cannot open source image: {e}")
        sys.exit(1)

    pixels = src.load()
    for y in range(src.height):
        for x in range(src.width):
            r, g, b, alpha = pixels[x, y]
            hue, _, value = __import__("colorsys").rgb_to_hsv(
                r / 255, g / 255, b / 255
            )
            if alpha <= 16 or hue >= 0.56 or value < 0.42 or g < 140 or b < 160:
                pixels[x, y] = (r, g, b, 0)

    bbox = src.getchannel("A").getbbox()
    if bbox is None:
        print("ERROR: Icon foreground is empty after background removal")
        sys.exit(1)
    src = src.crop(bbox)

    success = 0
    for density, size in MIPMAP_SIZES.items():
        mipmap_dir = os.path.join(dst_dir, f"mipmap-{density}")
        if not os.path.isdir(mipmap_dir):
            print(f"WARNING: mipmap dir not found: {mipmap_dir}, skipping")
            continue

        try:
            scale = min(size * 0.9 / src.width, size * 0.9 / src.height)
            resized = src.resize(
                (max(1, round(src.width * scale)), max(1, round(src.height * scale))),
                Image.Resampling.LANCZOS,
            )
            canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            canvas.alpha_composite(
                resized,
                ((size - resized.width) // 2, (size - resized.height) // 2),
            )
            for filename in (
                "ic_launcher_foreground.png",
                "ic_launcher.png",
                "ic_launcher_round.png",
            ):
                dst_path = os.path.join(mipmap_dir, filename)
                canvas.save(dst_path, "PNG")
            print(f"  Generated {density} ({size}x{size}) transparent LDesk icons")
            success += 1
        except Exception as e:
            print(f"ERROR: Failed to generate {density}: {e}")

    print(f"\nGenerated {success}/{len(MIPMAP_SIZES)} icon files.")
    if success == len(MIPMAP_SIZES):
        print("APK icons ready.")
    else:
        print("WARNING: Some icons were not generated!")
        sys.exit(1)

if __name__ == "__main__":
    main()
