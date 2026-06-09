#!/usr/bin/env python3
"""
Resize mac-icon.png for Android mipmap directories.
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
        src = Image.open(src_path)
        src_w, src_h = src.size
        print(f"Source: {src_path} ({src_w}x{src_h})")
    except Exception as e:
        print(f"ERROR: Cannot open source image: {e}")
        sys.exit(1)

    success = 0
    for density, size in MIPMAP_SIZES.items():
        mipmap_dir = os.path.join(dst_dir, f"mipmap-{density}")
        if not os.path.isdir(mipmap_dir):
            print(f"WARNING: mipmap dir not found: {mipmap_dir}, skipping")
            continue

        dst_path = os.path.join(mipmap_dir, "ic_launcher_foreground.png")

        try:
            # High-quality Lanczos resize
            resized = src.resize((size, size), Image.Resampling.LANCZOS)
            resized.save(dst_path, "PNG")
            print(f"  Generated {density} ({size}x{size}): {dst_path}")
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
