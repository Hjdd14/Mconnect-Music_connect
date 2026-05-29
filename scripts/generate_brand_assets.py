"""Generate Mconnect launcher and splash assets.

The mark combines an M monogram, a play triangle, sound waves, and three
connected source nodes to represent multi-platform music aggregation.
"""
from __future__ import annotations

import math
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ICON_DIR = ROOT / "assets" / "icon"
IMAGE_DIR = ROOT / "assets" / "images"
PREVIEW_DIR = ROOT / "build" / "brand_preview"

INK = (245, 248, 255, 255)
MUTED = (176, 187, 210, 255)
BG_TOP = (14, 20, 34)
BG_BOTTOM = (28, 34, 59)
BG_EDGE = (9, 12, 24)
NETEASE_RED = (255, 72, 96)
QQ_GREEN = (44, 217, 159)
KUGOU_GOLD = (255, 184, 76)
ELECTRIC_BLUE = (84, 166, 255)


def _resample_filter():
    return getattr(Image, "Resampling", Image).LANCZOS


def lerp(a: int, b: int, t: float) -> int:
    return int(a + (b - a) * t)


def mix(c1: tuple[int, int, int], c2: tuple[int, int, int], t: float):
    return tuple(lerp(c1[i], c2[i], t) for i in range(3))


def font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    names = [
        "C:/Windows/Fonts/segoeuib.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf",
        "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf",
        "C:/Windows/Fonts/calibrib.ttf" if bold else "C:/Windows/Fonts/calibri.ttf",
    ]
    for name in names:
        if os.path.exists(name):
            return ImageFont.truetype(name, size)
    return ImageFont.load_default()


def gradient_square(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    pix = img.load()
    cx = size * 0.52
    cy = size * 0.42
    max_dist = math.hypot(max(cx, size - cx), max(cy, size - cy))
    for y in range(size):
        vertical = y / (size - 1)
        base = mix(BG_TOP, BG_BOTTOM, vertical)
        for x in range(size):
            dx = x - cx
            dy = y - cy
            radial = min(1.0, math.hypot(dx, dy) / max_dist)
            color = mix(base, BG_EDGE, radial * 0.58)
            pix[x, y] = (*color, 255)
    return img


def rounded_panel(size: int, radius: int) -> Image.Image:
    bg = gradient_square(size)
    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    # Subtle diagonal beams keep the icon readable at small size.
    for i, color in enumerate((NETEASE_RED, QQ_GREEN, ELECTRIC_BLUE)):
        alpha = 35 - i * 5
        y = int(size * (0.22 + i * 0.18))
        draw.line(
            [(-size * 0.1, y), (size * 1.1, y + size * 0.38)],
            fill=(*color, alpha),
            width=max(4, size // 46),
        )

    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    g.ellipse(
        [size * 0.08, size * 0.07, size * 0.92, size * 0.9],
        fill=(84, 166, 255, 30),
    )
    g.ellipse(
        [size * 0.0, size * 0.18, size * 0.72, size * 1.04],
        fill=(255, 72, 96, 32),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(size // 11))
    bg.alpha_composite(glow)
    bg.alpha_composite(overlay)

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1],
        radius=radius,
        fill=255,
    )
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(bg, (0, 0), mask)
    return out


def draw_arc_line(
    draw: ImageDraw.ImageDraw,
    bbox: tuple[float, float, float, float],
    start: float,
    end: float,
    fill: tuple[int, int, int, int],
    width: int,
):
    draw.arc(bbox, start, end, fill=fill, width=width)


def draw_nodes(draw: ImageDraw.ImageDraw, scale: float, cx: float, cy: float):
    points = [
        (cx - 170 * scale, cy - 132 * scale, NETEASE_RED),
        (cx + 182 * scale, cy - 105 * scale, QQ_GREEN),
        (cx + 58 * scale, cy + 205 * scale, KUGOU_GOLD),
    ]
    line = (*MUTED[:3], 120)
    for a, b in ((0, 1), (1, 2), (2, 0)):
        p1 = points[a]
        p2 = points[b]
        draw.line([p1[:2], p2[:2]], fill=line, width=max(3, int(10 * scale)))
    for x, y, color in points:
        r = 28 * scale
        draw.ellipse([x - r, y - r, x + r, y + r], fill=(*color, 255))
        draw.ellipse(
            [x - r * 1.65, y - r * 1.65, x + r * 1.65, y + r * 1.65],
            outline=(*color, 80),
            width=max(2, int(7 * scale)),
        )


def draw_mark(
    img: Image.Image,
    center: tuple[float, float],
    size: float,
    include_nodes: bool = True,
    include_word: bool = False,
):
    draw = ImageDraw.Draw(img)
    cx, cy = center
    s = size / 512

    if include_nodes:
        draw_nodes(draw, s, cx, cy)

    # Outer sound wave arcs.
    for i, color in enumerate((NETEASE_RED, QQ_GREEN, ELECTRIC_BLUE)):
        radius = (224 + i * 34) * s
        width = max(5, int((14 - i) * s))
        alpha = 245 - i * 42
        bbox = (cx - radius, cy - radius, cx + radius, cy + radius)
        draw_arc_line(draw, bbox, 206, 332, (*color, alpha), width)
        draw_arc_line(draw, bbox, 28, 154, (*color, alpha), width)

    # Soft base behind the monogram.
    core_r = 158 * s
    core = Image.new("RGBA", img.size, (0, 0, 0, 0))
    cd = ImageDraw.Draw(core)
    cd.ellipse(
        [cx - core_r, cy - core_r, cx + core_r, cy + core_r],
        fill=(5, 8, 18, 168),
        outline=(255, 255, 255, 46),
        width=max(2, int(4 * s)),
    )
    core = core.filter(ImageFilter.GaussianBlur(max(1, int(1 * s))))
    img.alpha_composite(core)
    draw = ImageDraw.Draw(img)

    # M monogram as a thick ribbon.
    stroke = max(20, int(52 * s))
    pts = [
        (cx - 126 * s, cy + 112 * s),
        (cx - 126 * s, cy - 110 * s),
        (cx - 28 * s, cy + 26 * s),
        (cx + 72 * s, cy - 110 * s),
        (cx + 72 * s, cy + 112 * s),
    ]
    draw.line(pts, fill=INK, width=stroke, joint="curve")
    draw.line(pts, fill=(255, 255, 255, 70), width=max(4, stroke // 7), joint="curve")

    # Play triangle for music playback.
    tri = [
        (cx + 16 * s, cy - 44 * s),
        (cx + 16 * s, cy + 48 * s),
        (cx + 100 * s, cy + 2 * s),
    ]
    draw.polygon(tri, fill=(*KUGOU_GOLD, 255))

    # Small connection dot where the play mark meets the M.
    r = 18 * s
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*QQ_GREEN, 255))

    if include_word:
        title_font = font(int(72 * s), bold=True)
        subtitle_font = font(int(24 * s), bold=False)
        title = "Mconnect"
        subtitle = "music connected"
        tb = draw.textbbox((0, 0), title, font=title_font)
        sb = draw.textbbox((0, 0), subtitle, font=subtitle_font)
        draw.text(
            (cx - (tb[2] - tb[0]) / 2, cy + 282 * s),
            title,
            fill=INK,
            font=title_font,
        )
        draw.text(
            (cx - (sb[2] - sb[0]) / 2, cy + 360 * s),
            subtitle,
            fill=(*MUTED[:3], 210),
            font=subtitle_font,
        )


def save_downsampled(img: Image.Image, path: Path, size: tuple[int, int]):
    out = img.resize(size, _resample_filter())
    path.parent.mkdir(parents=True, exist_ok=True)
    out.save(path)


def make_launcher_icon():
    canvas = rounded_panel(2048, 430)
    draw_mark(canvas, (1024, 1024), 1220, include_nodes=True)
    save_downsampled(canvas, ICON_DIR / "app_icon.png", (1024, 1024))


def make_foreground_icon():
    canvas = Image.new("RGBA", (2048, 2048), (0, 0, 0, 0))
    draw_mark(canvas, (1024, 1024), 1220, include_nodes=True)
    save_downsampled(canvas, ICON_DIR / "app_icon_foreground.png", (1024, 1024))


def make_splash_logo():
    canvas = Image.new("RGBA", (2048, 2048), (0, 0, 0, 0))
    draw_mark(canvas, (1024, 840), 1180, include_nodes=True, include_word=True)
    save_downsampled(canvas, IMAGE_DIR / "splash_logo.png", (1024, 1024))


def make_preview():
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    icon = Image.open(ICON_DIR / "app_icon.png").resize((360, 360), _resample_filter())
    fg_bg = rounded_panel(360, 76)
    fg = Image.open(ICON_DIR / "app_icon_foreground.png").resize((360, 360), _resample_filter())
    fg_bg.alpha_composite(fg)
    splash_bg = gradient_square(360)
    splash = Image.open(IMAGE_DIR / "splash_logo.png").resize((300, 300), _resample_filter())
    splash_bg.alpha_composite(splash, (30, 20))

    preview = Image.new("RGB", (1240, 520), (18, 22, 34))
    draw = ImageDraw.Draw(preview)
    title_font = font(32, bold=True)
    label_font = font(20)
    draw.text((40, 34), "Mconnect brand preview", fill=INK, font=title_font)
    slots = [
        (60, 118, icon, "Launcher icon"),
        (440, 118, fg_bg, "Adaptive foreground"),
        (820, 118, splash_bg, "Splash logo"),
    ]
    for x, y, image, label in slots:
        preview.paste(image.convert("RGB"), (x, y))
        draw.text((x, y + 384), label, fill=MUTED, font=label_font)
    preview.save(PREVIEW_DIR / "mconnect_brand_preview.png")


def main():
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    make_launcher_icon()
    make_foreground_icon()
    make_splash_logo()
    make_preview()
    print(f"Generated {ICON_DIR / 'app_icon.png'}")
    print(f"Generated {ICON_DIR / 'app_icon_foreground.png'}")
    print(f"Generated {IMAGE_DIR / 'splash_logo.png'}")
    print(f"Generated {PREVIEW_DIR / 'mconnect_brand_preview.png'}")


if __name__ == "__main__":
    main()
