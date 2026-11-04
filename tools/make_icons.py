#!/usr/bin/env python3
"""Draws the app icon (light, dark and tinted variants) and the launch-screen mark.

Original artwork: flat shapes only, using the same suit geometry as SuitShape.swift.
Run from the repository root: python3 tools/make_icons.py
"""
import json, os
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(__file__), "..")
ASSETS = os.path.join(ROOT, "App", "Resources", "Assets.xcassets")
SS = 4  # supersampling


def hexrgb(h, a=255):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255, a)


def cubic(p0, p1, p2, p3, n=24):
    return [tuple(((1 - t) ** 3) * a + 3 * ((1 - t) ** 2) * t * b + 3 * (1 - t) * t * t * c + t ** 3 * d
                  for a, b, c, d in zip(p0, p1, p2, p3)) for t in [i / n for i in range(1, n + 1)]]


def quad(p0, p1, p2, n=20):
    return [tuple(((1 - t) ** 2) * a + 2 * (1 - t) * t * b + t * t * c for a, b, c in zip(p0, p1, p2))
            for t in [i / n for i in range(1, n + 1)]]


def stem():
    pts = [(0.5, 0.52)]
    pts += quad((0.5, 0.52), (0.47, 0.9), (0.28, 1.0))
    pts += [(0.72, 1.0)]
    pts += quad((0.72, 1.0), (0.53, 0.9), (0.5, 0.52))
    return pts


def suit_polygons(suit):
    """Lists of polygons (unit square) whose union is the suit."""
    if suit == "diamonds":
        pts = [(0.5, 0.0)]
        pts += quad((0.5, 0.0), (0.68, 0.3), (0.9, 0.5))
        pts += quad((0.9, 0.5), (0.68, 0.7), (0.5, 1.0))
        pts += quad((0.5, 1.0), (0.32, 0.7), (0.1, 0.5))
        pts += quad((0.1, 0.5), (0.32, 0.3), (0.5, 0.0))
        return [pts], []
    if suit == "hearts":
        pts = [(0.5, 0.27)]
        pts += cubic((0.5, 0.27), (0.4, 0.0), (0.0, 0.02), (0.0, 0.32))
        pts += cubic((0.0, 0.32), (0.0, 0.62), (0.36, 0.76), (0.5, 0.98))
        pts += cubic((0.5, 0.98), (0.64, 0.76), (1.0, 0.62), (1.0, 0.32))
        pts += cubic((1.0, 0.32), (1.0, 0.02), (0.6, 0.0), (0.5, 0.27))
        return [pts], []
    if suit == "spades":
        pts = [(0.5, 0.0)]
        pts += cubic((0.5, 0.0), (0.36, 0.2), (0.0, 0.3), (0.0, 0.56))
        pts += cubic((0.0, 0.56), (0.0, 0.8), (0.38, 0.84), (0.5, 0.62))
        pts += cubic((0.5, 0.62), (0.62, 0.84), (1.0, 0.8), (1.0, 0.56))
        pts += cubic((1.0, 0.56), (1.0, 0.3), (0.64, 0.2), (0.5, 0.0))
        return [pts, stem()], []
    if suit == "clubs":
        r = 0.215
        ellipses = [(0.5 - r, 0.04, 2 * r), (0.02, 0.38, 2 * r), (0.98 - 2 * r, 0.38, 2 * r), (0.34, 0.34, 0.32)]
        return [stem()], ellipses
    raise ValueError(suit)


def draw_suit(draw, suit, box, fill):
    x, y, w, h = box
    polys, ellipses = suit_polygons(suit)
    for poly in polys:
        draw.polygon([(x + px * w, y + py * h) for px, py in poly], fill=fill)
    for ex, ey, d in ellipses:
        draw.ellipse([x + ex * w, y + ey * h, x + (ex + d) * w, y + (ey + d) * h], fill=fill)


def card_layer(size, card_w, suit, face, ink, edge=None, edge_width=0.0, suit_scale=0.62, suit_shift=(0.0, 0.0)):
    """A single upright card with a big suit, on a transparent layer. `edge` draws an outline
    outside the card (used as a cut-out in the background colour so overlapping cards separate)."""
    card_h = card_w * 1.4
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x0, y0 = (size - card_w) / 2, (size - card_h) / 2
    if edge:
        e = card_w * edge_width
        d.rounded_rectangle([x0 - e, y0 - e, x0 + card_w + e, y0 + card_h + e], radius=card_w * 0.12 + e, fill=edge)
    d.rounded_rectangle([x0, y0, x0 + card_w, y0 + card_h], radius=card_w * 0.12, fill=face)
    s = card_w * suit_scale
    sx = x0 + (card_w - s) / 2 + suit_shift[0] * card_w
    sy = y0 + (card_h - s) / 2 + suit_shift[1] * card_h
    draw_suit(d, suit, (sx, sy, s, s), ink)
    return layer


def emblem(size, colors):
    """Two fanned cards: a heart behind, a spade in front."""
    big = size * SS
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    card_w = big * 0.38
    back = card_layer(big, card_w, "hearts", colors["face"], colors["red"], suit_scale=0.42, suit_shift=(-0.17, -0.2))
    back = back.rotate(14, resample=Image.BICUBIC, center=(big / 2, big / 2))
    back = back.transform(back.size, Image.AFFINE, (1, 0, big * 0.13, 0, 1, big * 0.03), resample=Image.BICUBIC)
    front = card_layer(big, card_w, "spades", colors["face"], colors["black"], colors["cut"], 0.05, suit_scale=0.58)
    front = front.rotate(-8, resample=Image.BICUBIC, center=(big / 2, big / 2))
    front = front.transform(front.size, Image.AFFINE, (1, 0, -big * 0.10, 0, 1, -big * 0.02), resample=Image.BICUBIC)
    canvas.alpha_composite(back)
    canvas.alpha_composite(front)
    return canvas


def icon(background, colors, out, tinted=False):
    big = 1024 * SS
    img = Image.new("RGBA", (big, big), hexrgb(background))
    img.alpha_composite(emblem(1024, colors))
    img = img.resize((1024, 1024), Image.LANCZOS)
    if tinted:
        img = img.convert("L").convert("RGB")
    else:
        img = img.convert("RGB")  # App Store icons must not have an alpha channel
    img.save(out, optimize=True)


def write_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def main():
    os.makedirs(ASSETS, exist_ok=True)
    write_json(os.path.join(ASSETS, "Contents.json"), {"info": {"author": "xcode", "version": 1}})

    iconset = os.path.join(ASSETS, "AppIcon.appiconset")
    os.makedirs(iconset, exist_ok=True)
    light = {"face": hexrgb(0xFFFFFF), "red": hexrgb(0xD7263D), "black": hexrgb(0x1B1B22), "cut": hexrgb(0x1DB37A)}
    dark = {"face": hexrgb(0x2B2E35), "red": hexrgb(0xFF6B72), "black": hexrgb(0xF2F2F5), "cut": hexrgb(0x0D2219)}
    tint = {"face": hexrgb(0xFFFFFF), "red": hexrgb(0x9A9A9A), "black": hexrgb(0x5A5A5A), "cut": hexrgb(0x000000)}
    icon(0x1DB37A, light, os.path.join(iconset, "AppIcon.png"))
    icon(0x0D2219, dark, os.path.join(iconset, "AppIcon-Dark.png"))
    icon(0x000000, tint, os.path.join(iconset, "AppIcon-Tinted.png"), tinted=True)
    write_json(os.path.join(iconset, "Contents.json"), {
        "images": [
            {"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": "AppIcon-Dark.png",
             "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            {"appearances": [{"appearance": "luminosity", "value": "tinted"}], "filename": "AppIcon-Tinted.png",
             "idiom": "universal", "platform": "ios", "size": "1024x1024"},
        ],
        "info": {"author": "xcode", "version": 1},
    })

    mark = os.path.join(ASSETS, "LaunchMark.imageset")
    os.makedirs(mark, exist_ok=True)
    # The launch mark is the icon itself with rounded corners, so launch feels continuous.
    base = Image.open(os.path.join(iconset, "AppIcon.png")).convert("RGBA").resize((1024 * SS // 2,) * 2, Image.LANCZOS)
    mask = Image.new("L", base.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, base.size[0] - 1, base.size[1] - 1], radius=base.size[0] * 0.2237, fill=255)
    base.putalpha(mask)
    for scale in (2, 3):
        base.resize((120 * scale, 120 * scale), Image.LANCZOS).save(os.path.join(mark, f"LaunchMark@{scale}x.png"), optimize=True)
    write_json(os.path.join(mark, "Contents.json"), {
        "images": [
            {"idiom": "universal", "scale": "1x"},
            {"filename": "LaunchMark@2x.png", "idiom": "universal", "scale": "2x"},
            {"filename": "LaunchMark@3x.png", "idiom": "universal", "scale": "3x"},
        ],
        "info": {"author": "xcode", "version": 1},
    })

    def colorset(name, light_hex, dark_hex):
        path = os.path.join(ASSETS, f"{name}.colorset")
        os.makedirs(path, exist_ok=True)

        def comp(h):
            r, g, b, _ = hexrgb(h)
            return {"color-space": "srgb", "components": {"red": f"0x{r:02X}", "green": f"0x{g:02X}",
                                                          "blue": f"0x{b:02X}", "alpha": "1.000"}}
        write_json(os.path.join(path, "Contents.json"), {
            "colors": [
                {"idiom": "universal", "color": comp(light_hex)},
                {"appearances": [{"appearance": "luminosity", "value": "dark"}], "idiom": "universal",
                 "color": comp(dark_hex)},
            ],
            "info": {"author": "xcode", "version": 1},
        })

    colorset("LaunchBackground", 0xF6F4EE, 0x0F0F12)
    colorset("AccentColor", 0x0A7A50, 0x3EDC9A)
    print("icons written to", os.path.abspath(ASSETS))


if __name__ == "__main__":
    main()
