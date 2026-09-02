#!/usr/bin/env python3
"""
Generate LDesk launcher icons for Android mipmaps directly from the PC icon
res/icon.png (1024x1024, full-bleed monitor glyph, no background).

Run this BEFORE the Flutter build step in CI. The mobile icon must look
identical to the desktop icon: same artwork, no redraw, no shrink, no bg.

Usage: python3 res/resize_for_apk.py
"""
import os
import sys

from PIL import Image

# Resize targets: density -> tile size
MIPMAP_SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

SOURCE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon.png")


def main():
    src = Image.open(SOURCE)
    if src.mode != "RGBA":
        src = src.convert("RGBA")

    dst_dir = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "flutter", "android", "app", "src", "main", "res",
    )

    success = 0
    for density, size in MIPMAP_SIZES.items():
        mipmap_dir = os.path.join(dst_dir, f"mipmap-{density}")
        if not os.path.isdir(mipmap_dir):
            print(f"WARNING: mipmap dir not found: {mipmap_dir}, skipping")
            continue
        icon = src.resize((size, size), Image.Resampling.LANCZOS)
        for name in (
            "ic_launcher.png",
            "ic_launcher_round.png",
            "ic_launcher_legacy.png",
            "ic_launcher_foreground.png",
        ):
            icon.save(os.path.join(mipmap_dir, name), "PNG")
        print(f"  Generated {density} ({size}x{size}) from res/icon.png")
        success += 1

    print(f"\nGenerated {success}/{len(MIPMAP_SIZES)} icon files.")
    if success == len(MIPMAP_SIZES):
        print("APK icons ready (same artwork as PC).")
    else:
        print("WARNING: Some icons were not generated!")
        sys.exit(1)


if __name__ == "__main__":
    main()