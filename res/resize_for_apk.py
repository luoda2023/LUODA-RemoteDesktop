#!/usr/bin/env python3
"""
Create transparent LDesk launcher icons (monitor glyph) for Android mipmaps.
Run this BEFORE the Flutter build step in CI.

The launcher icon is the LUODA/LDesk monitor symbol: a bright-cyan monitor
with a dark-blue screen and stand, drawn on a fully transparent tile (no
background). Sizes are chosen so the glyph is not clipped by launcher masks.

Usage: python3 res/resize_for_apk.py
"""
import math
import os
import sys

from PIL import Image, ImageDraw

# Resize targets: density -> tile size
MIPMAP_SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

MASTER = 1024
# Legacy icons: glyph width as a fraction of the tile.
LEGACY_GLYPH_W = 0.62
# Adaptive foreground: keep the glyph inside the 66/108dp safe circle.
ADAPTIVE_MAX_RADIUS = 0.29

# Brand colors sampled from res/mac-icon.png.
CYAN_START = (0x51, 0xF1, 0xFD)
CYAN_END = (0x26, 0xC3, 0xF8)
SCREEN_START = (0x15, 0x52, 0x8E)
SCREEN_END = (0x0E, 0x3F, 0x75)


def _lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _gradient(size, start, end):
    img = Image.new("RGB", (size, size))
    px = img.load()
    denom = 2 * (size - 1) or 1
    for y in range(size):
        for x in range(size):
            px[x, y] = _lerp(start, end, (x + y) / denom)
    return img


def _draw_glyph(size, glyph_w):
    """Return a transparent RGBA canvas with the centered monitor glyph."""
    glyph_h = glyph_w * 35 / 30
    x0 = (size - glyph_w) / 2
    y0 = (size - glyph_h) / 2

    def P(gx, gy):
        return (x0 + gx * glyph_w, y0 + gy * glyph_h)

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cyan = _gradient(size, CYAN_START, CYAN_END)
    screen = _gradient(size, SCREEN_START, SCREEN_END)

    body = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(body)
    d.rounded_rectangle([P(0, 0), P(1, 0.6286)], radius=0.07 * glyph_w, fill=255)
    d.polygon(
        [
            P(0.3333, 0.7143),
            P(0.6667, 0.7143),
            P(0.60, 0.8571),
            P(0.40, 0.8571),
        ],
        fill=255,
    )
    d.ellipse([P(0.10, 0.8286), P(0.90, 1.0)], fill=255)
    canvas.paste(cyan, (0, 0), body)

    screen_mask = Image.new("L", (size, size), 0)
    ds = ImageDraw.Draw(screen_mask)
    ds.rounded_rectangle(
        [P(0.10, 0.0857), P(0.90, 0.5429)], radius=0.033 * glyph_w, fill=255
    )
    canvas.paste(screen, (0, 0), screen_mask)
    return canvas


def _max_radius(img):
    alpha = img.getchannel("A")
    n = img.size[0]
    cx = (n - 1) / 2
    cy = (n - 1) / 2
    px = alpha.load()
    best = 0.0
    for y in range(n):
        for x in range(n):
            if px[x, y] > 32:
                r = math.hypot(x - cx, y - cy)
                if r > best:
                    best = r
    return best


def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(base_dir)
    dst_dir = os.path.join(
        repo_root, "flutter", "android", "app", "src", "main", "res"
    )

    legacy_master = _draw_glyph(MASTER, MASTER * LEGACY_GLYPH_W)
    radius = _max_radius(legacy_master)
    adaptive_scale = ADAPTIVE_MAX_RADIUS * MASTER / radius
    print(
        f"Master glyph: {MASTER}x{MASTER}, max radius {radius:.1f}, "
        f"adaptive scale {adaptive_scale:.3f}"
    )

    success = 0
    for density, size in MIPMAP_SIZES.items():
        mipmap_dir = os.path.join(dst_dir, f"mipmap-{density}")
        if not os.path.isdir(mipmap_dir):
            print(f"WARNING: mipmap dir not found: {mipmap_dir}, skipping")
            continue
        try:
            legacy = legacy_master.resize((size, size), Image.Resampling.LANCZOS)

            asz = max(1, round(MASTER * adaptive_scale))
            glyph_at_target = legacy_master.resize(
                (max(1, asz * size // MASTER), max(1, asz * size // MASTER)),
                Image.Resampling.LANCZOS,
            )
            adaptive = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            off = (size - glyph_at_target.size[0]) // 2
            adaptive.paste(glyph_at_target, (off, off), glyph_at_target)

            legacy.save(os.path.join(mipmap_dir, "ic_launcher_legacy.png"), "PNG")
            adaptive.save(
                os.path.join(mipmap_dir, "ic_launcher_foreground.png"), "PNG"
            )
            legacy.save(os.path.join(mipmap_dir, "ic_launcher.png"), "PNG")
            legacy.save(os.path.join(mipmap_dir, "ic_launcher_round.png"), "PNG")
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
