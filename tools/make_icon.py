#!/usr/bin/env python3
"""Draw the 25-40 app icon: an ivory playing card that reads like the title
logo, an impossible 25 over the logo's gold-rimmed gem over 40, in the
game's lacquer red, tilted on the dark wood of the card room under its lamp.

Uses the game's own Playfair Display, its lining figures as the title logo
sets them. Writes, for the Godot client:
  godot/icon.png   1024 px, full bleed (window, Windows, Steam)
  godot/icon.ico   16-256 px, full bleed
  godot/icon.icns  macOS, on Apple's icon grid with its margin and shadow
and the masters under art/ikon/. Needs Pillow, numpy and fontTools; the
.icns needs macOS `iconutil`.
"""

import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT = ROOT / "godot" / "assets" / "fonts" / "PlayfairDisplay.ttf"
GODOT = ROOT / "godot"
MASTERS = ROOT / "art" / "ikon"
S = 2048  # drawn at twice the master size, then scaled down

ESPRESSO_TOP = (58, 33, 21)
ESPRESSO_LOW = (16, 10, 7)
LAMP = (255, 186, 104)
IVORY = (246, 239, 222)
CARD_EDGE = (184, 168, 140)
LACQUER = (168, 36, 30)
GOLD_LINE = (201, 164, 76, 95)


def lining_font(work: Path, weight: int) -> Path:
    # Playfair's digits are old-style by default; the title logo uses the
    # lining ones (".lf"), so map the digits to those in a static instance.
    font = instancer.instantiateVariableFont(TTFont(FONT), {"wght": weight})
    names = set(font.getGlyphOrder())
    for table in font["cmap"].tables:
        for code in range(ord("0"), ord("9") + 1):
            if code in table.cmap and table.cmap[code] + ".lf" in names:
                table.cmap[code] = table.cmap[code] + ".lf"
    path = work / f"playfair-lf-{weight}.ttf"
    font.save(path)
    return path


def background(size: int) -> Image.Image:
    # Dark wood, warmer toward the top where the lamp hangs over the table.
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    t = (y / size) ** 0.9
    base = np.stack([np.array(ESPRESSO_TOP[i]) + (ESPRESSO_LOW[i] - ESPRESSO_TOP[i]) * t for i in range(3)], -1)
    d = np.hypot(x - size * 0.5, (y - size * 0.16) * 1.15) / (size * 0.62)
    g = (np.clip(1.0 - d, 0.0, 1.0) ** 2.2 * 0.42)[..., None]
    lit = base + (np.array(LAMP, np.float32) - base) * g
    return Image.fromarray(np.clip(lit, 0, 255).astype(np.uint8), "RGB")


def gem(d: ImageDraw.ImageDraw, cx: float, cy: float, w: float, h: float) -> None:
    # The logo's gem: lacquer red, a lit and a shaded facet, in gold.
    def diamond(k: float) -> list:
        return [(cx, cy - h / 2 * k), (cx + w / 2 * k, cy), (cx, cy + h / 2 * k), (cx - w / 2 * k, cy)]

    d.polygon(diamond(1.28), fill=(250, 222, 150))
    d.polygon(diamond(1.12), fill=(120, 74, 24))
    d.polygon(diamond(1.0), fill=(176, 40, 32))
    d.polygon([(cx, cy - h / 2), (cx, cy), (cx - w / 2, cy)], fill=(214, 70, 52))
    d.polygon([(cx, cy + h / 2), (cx, cy), (cx + w / 2, cy)], fill=(118, 22, 18))


def card(size: int, bold: Path) -> Image.Image:
    # The card upright: big 25, the gem under it with a gold rule either
    # side, 40 under that, the corner index, then turned a few degrees as
    # if just dealt.
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w, h = size * 0.52, size * 0.73
    x0, y0 = (size - w) / 2, (size - h) / 2
    d.rounded_rectangle([x0, y0, x0 + w, y0 + h], radius=w * 0.09, fill=IVORY + (255,), outline=CARD_EDGE + (255,), width=max(2, size // 500))
    d.text((x0 + w / 2, y0 + h * 0.31), "25", font=ImageFont.truetype(str(bold), int(w * 0.54)), fill=LACQUER + (255,), anchor="mm")
    rule_y = y0 + h * 0.585
    for side in (-1, 1):
        a, b = x0 + w / 2 + side * w * 0.11, x0 + w / 2 + side * w * 0.33
        d.line([(min(a, b), rule_y), (max(a, b), rule_y)], fill=(184, 140, 60, 255), width=max(2, size // 340))
    gem(d, x0 + w / 2, rule_y, w * 0.12, w * 0.17)
    d.text((x0 + w / 2, y0 + h * 0.775), "40", font=ImageFont.truetype(str(bold), int(w * 0.36)), fill=LACQUER + (255,), anchor="mm")
    d.text((x0 + w * 0.15, y0 + h * 0.095), "25", font=ImageFont.truetype(str(bold), int(w * 0.15)), fill=LACQUER + (255,), anchor="mm")
    small = w * 0.034
    cx, cy = x0 + w * 0.15, y0 + h * 0.178
    d.polygon([(cx, cy - small), (cx + small * 0.72, cy), (cx, cy + small), (cx - small * 0.72, cy)], fill=LACQUER + (255,))
    return layer.rotate(8, resample=Image.BICUBIC, center=(size / 2, size / 2))


def art(bold: Path) -> Image.Image:
    img = background(S).convert("RGBA")
    face = card(S, bold)
    shade = face.split()[3].filter(ImageFilter.GaussianBlur(S * 0.02))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 150), (int(S * 0.012), int(S * 0.03)), shade)
    img = Image.alpha_composite(img, shadow)
    return Image.alpha_composite(img, face)


def tile(img: Image.Image, inset_frac: float, radius_frac: float, shadow: bool) -> Image.Image:
    # Cut to a rounded square with a gold hairline just inside its edge;
    # macOS icons also sit inside a margin, on a soft shadow.
    size = img.size[0]
    inset = int(size * inset_frac)
    radius = int((size - 2 * inset) * radius_frac)
    if inset > 0:
        # The whole picture shrinks into the tile rather than being cropped.
        inner = img.resize((size - 2 * inset, size - 2 * inset), Image.LANCZOS)
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        img.paste(inner, (inset, inset))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([inset, inset, size - 1 - inset, size - 1 - inset], radius=radius, fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if shadow:
        blur = mask.filter(ImageFilter.GaussianBlur(size * 0.012))
        drop = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        drop.paste((0, 0, 0, 110), (0, int(size * 0.01)), blur)
        out = Image.alpha_composite(out, drop)
    cut = img.copy()
    cut.putalpha(mask)
    out = Image.alpha_composite(out, cut)
    k = int((size - 2 * inset) * 0.045)
    ImageDraw.Draw(out).rounded_rectangle(
        [inset + k, inset + k, size - 1 - inset - k, size - 1 - inset - k],
        radius=max(radius - k, 4), outline=GOLD_LINE, width=max(2, size // 400),
    )
    return out.resize((1024, 1024), Image.LANCZOS)


def main() -> None:
    MASTERS.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        drawn = art(lining_font(work, 900))
        full = tile(drawn, 0.0, 0.2, False)
        mac = tile(drawn, 100 / 1024, 0.225, True)
        full.save(MASTERS / "icon-1024.png")
        mac.save(MASTERS / "icon-macos-1024.png")
        full.save(GODOT / "icon.png")
        full.save(GODOT / "icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
        if shutil.which("iconutil"):
            iconset = work / "icon.iconset"
            iconset.mkdir()
            for points in (16, 32, 128, 256, 512):
                for scale in (1, 2):
                    px = points * scale
                    name = f"icon_{points}x{points}" + ("@2x" if scale == 2 else "") + ".png"
                    mac.resize((px, px), Image.LANCZOS).save(iconset / name)
            subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(GODOT / "icon.icns")], check=True)
        else:
            print("iconutil not found: icon.icns not written (macOS only)")
    print("wrote", GODOT / "icon.png", GODOT / "icon.ico", GODOT / "icon.icns")


if __name__ == "__main__":
    main()
