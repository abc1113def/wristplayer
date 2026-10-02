"""Generates the 1024x1024 app icons for iOS and watchOS asset catalogs.

Run: python scripts/make_icons.py
"""
import json
import os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def gradient(top, bottom):
    img = Image.new("RGB", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            t = (x * 0.35 + y * 0.65) / SIZE
            px[x, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return img


def music_note(draw, cx, cy, scale, fill):
    # Two eighth-note heads joined by a beam.
    head_w, head_h = 170 * scale, 128 * scale
    stem_w = 40 * scale
    left_x, right_x = cx - 190 * scale, cx + 150 * scale
    head_y = cy + 170 * scale
    top_y = cy - 250 * scale
    for hx, hy in ((left_x, head_y), (right_x, head_y - 60 * scale)):
        draw.ellipse([hx - head_w / 2, hy - head_h / 2, hx + head_w / 2, hy + head_h / 2], fill=fill)
        sx = hx + head_w / 2 - stem_w
        draw.rectangle([sx, (top_y if hx == left_x else top_y - 60 * scale) + 20 * scale, sx + stem_w, hy], fill=fill)
    lsx = left_x + head_w / 2 - stem_w
    rsx = right_x + head_w / 2
    beam_h = 95 * scale
    draw.polygon([
        (lsx, top_y), (rsx, top_y - 60 * scale),
        (rsx, top_y - 60 * scale + beam_h), (lsx, top_y + beam_h),
    ], fill=fill)


def make_icon(path):
    img = gradient((255, 94, 98), (124, 58, 237))
    glow = Image.new("L", (SIZE, SIZE), 0)
    gd = ImageDraw.Draw(glow)
    gd.ellipse([180, 160, 844, 824], fill=110)
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    img = Image.composite(Image.new("RGB", (SIZE, SIZE), (255, 255, 255)), img, glow.point(lambda v: v // 3))
    draw = ImageDraw.Draw(img)
    # soft shadow
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    music_note(ImageDraw.Draw(shadow), SIZE / 2 + 10, SIZE / 2 + 24, 1.0, (40, 0, 60, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    img.paste(shadow, (0, 0), shadow)
    music_note(draw, SIZE / 2, SIZE / 2, 1.0, (255, 255, 255))
    img.save(path, "PNG")


def write_catalog(catalog, platform):
    os.makedirs(os.path.join(catalog, "AppIcon.appiconset"), exist_ok=True)
    os.makedirs(os.path.join(catalog, "AccentColor.colorset"), exist_ok=True)
    with open(os.path.join(catalog, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
    make_icon(os.path.join(catalog, "AppIcon.appiconset", "icon-1024.png"))
    with open(os.path.join(catalog, "AppIcon.appiconset", "Contents.json"), "w") as f:
        json.dump({
            "images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": platform, "size": "1024x1024"}],
            "info": {"author": "xcode", "version": 1},
        }, f, indent=2)
    with open(os.path.join(catalog, "AccentColor.colorset", "Contents.json"), "w") as f:
        json.dump({
            "colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {
                "red": "1.000", "green": "0.369", "blue": "0.384", "alpha": "1.000"}}}],
            "info": {"author": "xcode", "version": 1},
        }, f, indent=2)


if __name__ == "__main__":
    write_catalog(os.path.join(ROOT, "iOS", "Assets.xcassets"), "ios")
    write_catalog(os.path.join(ROOT, "Watch", "Assets.xcassets"), "watchos")
    print("icons written")
