"""Generate app icon and splash screen for Mconnect."""
from PIL import Image, ImageDraw, ImageFont
import math
import os

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(BASE, "assets", "icon")
IMG_DIR = os.path.join(BASE, "assets", "images")

# Brand colors
PINK = (233, 30, 99)       # #E91E63
DARK_PINK = (194, 24, 77)  # #C2185B
WHITE = (255, 255, 255)


def draw_music_note(draw, cx, cy, size, color):
    """Draw a stylized music note."""
    # Note head (filled circle)
    head_r = size * 0.28
    head_cx = cx - size * 0.15
    head_cy = cy + size * 0.25
    draw.ellipse(
        [head_cx - head_r, head_cy - head_r, head_cx + head_r, head_cy + head_r],
        fill=color,
    )

    # Stem (vertical line)
    stem_w = size * 0.06
    stem_top = cy - size * 0.35
    stem_bottom = head_cy
    draw.rectangle(
        [head_cx + head_r * 0.5 - stem_w / 2, stem_top, head_cx + head_r * 0.5 + stem_w / 2, stem_bottom],
        fill=color,
    )

    # Flag (curved)
    flag_w = size * 0.22
    flag_h = size * 0.18
    flag_x = head_cx + head_r * 0.5 + stem_w / 2
    flag_y = stem_top
    points = []
    for i in range(20):
        t = i / 19.0
        x = flag_x + flag_w * t
        y = flag_y + flag_h * math.sin(t * math.pi * 0.8)
        points.append((x, y))
    # Close the flag shape
    for i in range(19, -1, -1):
        t = i / 19.0
        x = flag_x + flag_w * t * 0.3
        y = flag_y + flag_h * math.sin(t * math.pi * 0.8) * 0.3
        points.append((x, y))
    if len(points) >= 3:
        draw.polygon(points, fill=color)


def draw_sound_waves(draw, cx, cy, size, color):
    """Draw sound wave arcs."""
    for i, r in enumerate([0.52, 0.62, 0.72]):
        arc_r = size * r
        alpha = 255 - i * 60
        wave_color = (*color[:3], alpha) if len(color) == 4 else color
        # Right side waves
        bbox = [cx - arc_r, cy - arc_r, cx + arc_r, cy + arc_r]
        draw.arc(bbox, start=-40, end=40, fill=wave_color, width=max(2, int(size * 0.03)))
        # Left side waves (mirror)
        draw.arc(bbox, start=140, end=220, fill=wave_color, width=max(2, int(size * 0.03)))


def generate_app_icon():
    """Generate 1024x1024 app icon with gradient-like background."""
    size = 1024
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Gradient background (manual radial gradient simulation)
    for y in range(size):
        for x in range(0, size, 4):  # Step by 4 for speed
            dx = (x - size / 2) / (size / 2)
            dy = (y - size / 2) / (size / 2)
            dist = math.sqrt(dx * dx + dy * dy)
            t = min(1.0, dist)

            r = int(PINK[0] + (DARK_PINK[0] - PINK[0]) * t)
            g = int(PINK[1] + (DARK_PINK[1] - PINK[1]) * t)
            b = int(PINK[2] + (DARK_PINK[2] - PINK[2]) * t)

            for xx in range(x, min(x + 4, size)):
                draw.point((xx, y), fill=(r, g, b, 255))

    # Draw sound waves
    draw_sound_waves(draw, size // 2, size // 2, size, WHITE)

    # Draw music note
    draw_music_note(draw, size // 2, size // 2, size * 0.55, WHITE)

    # Round corners (for adaptive icon we'll handle separately)
    return img


def generate_foreground():
    """Generate 432x432 adaptive icon foreground (transparent bg, centered content)."""
    size = 432
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Draw sound waves
    draw_sound_waves(draw, size // 2, size // 2, size, WHITE)

    # Draw music note
    draw_music_note(draw, size // 2, size // 2, size * 0.55, WHITE)

    return img


def generate_splash():
    """Generate 1080x1920 splash screen."""
    w, h = 1080, 1920
    img = Image.new("RGBA", (w, h), (*PINK, 255))
    draw = ImageDraw.Draw(img)

    # Subtle gradient overlay
    for y in range(h):
        t = y / h
        r = int(PINK[0] * (1 - t * 0.3) + DARK_PINK[0] * t * 0.3)
        g = int(PINK[1] * (1 - t * 0.3) + DARK_PINK[1] * t * 0.3)
        b = int(PINK[2] * (1 - t * 0.3) + DARK_PINK[2] * t * 0.3)
        draw.line([(0, y), (w, y)], fill=(r, g, b, 255))

    # Draw music note centered
    note_size = 300
    cx, cy = w // 2, h // 2 - 80
    draw_music_note(draw, cx, cy, note_size, WHITE)
    draw_sound_waves(draw, cx, cy, note_size, WHITE)

    # App name text
    try:
        # Try to find a system font
        font_paths = [
            "C:/Windows/Fonts/segoeui.ttf",
            "C:/Windows/Fonts/arial.ttf",
            "C:/Windows/Fonts/calibri.ttf",
        ]
        font = None
        for fp in font_paths:
            if os.path.exists(fp):
                font = ImageFont.truetype(fp, 72)
                break
        if font is None:
            font = ImageFont.load_default()
    except Exception:
        font = ImageFont.load_default()

    # Draw "Mconnect" text
    text = "Mconnect"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    draw.text(((w - tw) // 2, cy + note_size * 0.5 + 40), text, fill=WHITE, font=font)

    return img


if __name__ == "__main__":
    os.makedirs(ICON_DIR, exist_ok=True)
    os.makedirs(IMG_DIR, exist_ok=True)

    print("Generating app icon (1024x1024)...")
    icon = generate_app_icon()
    icon.save(os.path.join(ICON_DIR, "app_icon.png"))
    print(f"  -> {ICON_DIR}/app_icon.png")

    print("Generating adaptive foreground (432x432)...")
    fg = generate_foreground()
    fg.save(os.path.join(ICON_DIR, "app_icon_foreground.png"))
    print(f"  -> {ICON_DIR}/app_icon_foreground.png")

    print("Generating splash screen (1080x1920)...")
    splash = generate_splash()
    splash.save(os.path.join(IMG_DIR, "splash_logo.png"))
    print(f"  -> {IMG_DIR}/splash_logo.png")

    print("Done!")
