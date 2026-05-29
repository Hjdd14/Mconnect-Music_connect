"""Generate app icon v2 — M-centric design with sound wave motif."""
from PIL import Image, ImageDraw, ImageFont
import math
import os

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(BASE, "assets", "icon")
IMG_DIR = os.path.join(BASE, "assets", "images")

PINK = (233, 30, 99)
DARK_PINK = (173, 20, 87)
DEEP_PINK = (136, 14, 79)
WHITE = (255, 255, 255)


def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def draw_rounded_rect(draw, bbox, radius, fill):
    x0, y0, x1, y1 = bbox
    draw.rectangle([x0 + radius, y0, x1 - radius, y1], fill=fill)
    draw.rectangle([x0, y0 + radius, x1, y1 - radius], fill=fill)
    draw.pieslice([x0, y0, x0 + 2 * radius, y0 + 2 * radius], 180, 270, fill=fill)
    draw.pieslice([x1 - 2 * radius, y0, x1, y0 + 2 * radius], 270, 360, fill=fill)
    draw.pieslice([x0, y1 - 2 * radius, x0 + 2 * radius, y1], 90, 180, fill=fill)
    draw.pieslice([x1 - 2 * radius, y1 - 2 * radius, x1, y1], 0, 90, fill=fill)


def draw_m_letter(img, cx, cy, m_width, m_height, color, stroke_w):
    """Draw a bold, stylized M letter with sound-wave-inspired serifs."""
    draw = ImageDraw.Draw(img)
    half_w = m_width / 2
    leg_w = m_width * 0.18
    v_depth = m_height * 0.35

    # Left leg
    left_x0 = cx - half_w
    left_x1 = left_x0 + leg_w
    draw.rectangle([left_x0, cy - m_height / 2, left_x1, cy + m_height / 2], fill=color)

    # Right leg
    right_x1 = cx + half_w
    right_x0 = right_x1 - leg_w
    draw.rectangle([right_x0, cy - m_height / 2, right_x1, cy + m_height / 2], fill=color)

    # Left diagonal (top-left to center V)
    left_diag_pts = [
        (left_x0, cy - m_height / 2),
        (left_x1, cy - m_height / 2),
        (cx, cy - m_height / 2 + v_depth),
        (cx - leg_w * 0.6, cy - m_height / 2 + v_depth),
    ]
    draw.polygon(left_diag_pts, fill=color)

    # Right diagonal (top-right to center V)
    right_diag_pts = [
        (right_x0, cy - m_height / 2),
        (right_x1, cy - m_height / 2),
        (cx + leg_w * 0.6, cy - m_height / 2 + v_depth),
        (cx, cy - m_height / 2 + v_depth),
    ]
    draw.polygon(right_diag_pts, fill=color)

    # Center V fill
    v_pts = [
        (cx - leg_w * 0.8, cy - m_height / 2 + v_depth - leg_w * 0.3),
        (cx + leg_w * 0.8, cy - m_height / 2 + v_depth - leg_w * 0.3),
        (cx + leg_w * 0.3, cy - m_height / 2 + v_depth + leg_w * 0.2),
        (cx - leg_w * 0.3, cy - m_height / 2 + v_depth + leg_w * 0.2),
    ]
    draw.polygon(v_pts, fill=color)


def draw_sound弧(draw, cx, cy, size, color, count=3):
    """Draw concentric sound wave arcs around the M."""
    for i in range(count):
        r = size * (0.55 + i * 0.12)
        w = max(3, int(size * 0.028))
        # Right arc
        bbox = [cx - r, cy - r, cx + r, cy + r]
        draw.arc(bbox, -50, 50, fill=color, width=w)
        # Left arc
        draw.arc(bbox, 130, 230, fill=color, width=w)


def draw_dot_matrix(img, cx, cy, m_width, m_height, color):
    """Draw a subtle dot grid behind the M for texture."""
    draw = ImageDraw.Draw(img)
    spacing = 18
    dot_r = 2
    for row_y in range(int(cy - m_height * 0.7), int(cy + m_height * 0.7), spacing):
        for col_x in range(int(cx - m_width * 0.8), int(cx + m_width * 0.8), spacing):
            # Skip dots that would overlap the M area
            dx = abs(col_x - cx)
            dy = abs(row_y - cy)
            if dx < m_width * 0.42 and dy < m_height * 0.55:
                continue
            # Fade based on distance from center
            dist = math.sqrt(dx**2 + dy**2) / (m_width * 0.8)
            if dist > 1.2:
                continue
            alpha = max(0, min(255, int(40 * (1 - dist * 0.7))))
            c = (*color[:3], alpha)
            draw.ellipse([col_x - dot_r, row_y - dot_r, col_x + dot_r, row_y + dot_r], fill=c)


def generate_icon_v2():
    """Main app icon 1024x1024 — gradient + M + sound arcs + dot texture."""
    size = 1024
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Radial gradient background
    cx, cy = size // 2, size // 2
    max_r = size * 0.75
    for y in range(size):
        for x in range(0, size, 2):
            dx = x - cx
            dy = y - cy
            dist = math.sqrt(dx * dx + dy * dy)
            t = min(1.0, dist / max_r)
            c = lerp_color(PINK, DEEP_PINK, t * t)
            draw.point((x, y), fill=(*c, 255))
            draw.point((x + 1, y), fill=(*c, 255))

    # Dot matrix texture
    draw_dot_matrix(img, cx, cy, size * 0.6, size * 0.5, WHITE)

    # Sound wave arcs
    draw_sound弧(draw, cx, cy, size, WHITE, count=3)

    # M letter
    draw_m_letter(img, cx, cy + size * 0.02, size * 0.38, size * 0.38, WHITE, 0)

    return img


def generate_foreground_v2():
    """Adaptive icon foreground 432x432 — just the M + arcs on transparent."""
    size = 432
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cx, cy = size // 2, size // 2

    draw_dot_matrix(img, cx, cy, size * 0.6, size * 0.5, WHITE)
    draw_sound弧(ImageDraw.Draw(img), cx, cy, size, WHITE, count=3)
    draw_m_letter(img, cx, cy + size * 0.02, size * 0.38, size * 0.38, WHITE, 0)

    return img


def generate_splash_v2():
    """Splash screen 1080x1920 — centered M + name text."""
    w, h = 1080, 1920
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Gradient background
    for y in range(h):
        t = y / h
        c = lerp_color(PINK, DEEP_PINK, t * 0.6)
        draw.line([(0, y), (w, y)], fill=(*c, 255))

    cx, cy = w // 2, h // 2 - 100

    # Dot matrix
    draw_dot_matrix(img, cx, cy, w * 0.5, 400, WHITE)

    # Sound arcs
    draw_sound弧(draw, cx, cy, w * 0.55, WHITE, count=3)

    # M letter
    draw_m_letter(img, cx, cy, 260, 260, WHITE, 0)

    # App name
    try:
        font = None
        for fp in ["C:/Windows/Fonts/segoeuil.ttf", "C:/Windows/Fonts/arial.ttf", "C:/Windows/Fonts/calibri.ttf"]:
            if os.path.exists(fp):
                font = ImageFont.truetype(fp, 64)
                break
        if font is None:
            font = ImageFont.load_default()
    except Exception:
        font = ImageFont.load_default()

    name = "Mconnect"
    bbox = draw.textbbox((0, 0), name, font=font)
    tw = bbox[2] - bbox[0]
    draw.text(((w - tw) // 2, cy + 180), name, fill=WHITE, font=font)

    # Tagline
    try:
        tag_font = None
        for fp in ["C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/arial.ttf"]:
            if os.path.exists(fp):
                tag_font = ImageFont.truetype(fp, 28)
                break
    except Exception:
        tag_font = None

    if tag_font:
        tagline = "Multi-platform Music Aggregator"
        bbox2 = draw.textbbox((0, 0), tagline, font=tag_font)
        tw2 = bbox2[2] - bbox2[0]
        draw.text(((w - tw2) // 2, cy + 260), tagline, fill=(*WHITE[:3], 180), font=tag_font)

    return img


if __name__ == "__main__":
    os.makedirs(ICON_DIR, exist_ok=True)
    os.makedirs(IMG_DIR, exist_ok=True)

    print("Generating icon v2 (1024x1024)...")
    icon = generate_icon_v2()
    icon.save(os.path.join(ICON_DIR, "app_icon.png"))
    print(f"  -> {ICON_DIR}/app_icon.png")

    print("Generating foreground v2 (432x432)...")
    fg = generate_foreground_v2()
    fg.save(os.path.join(ICON_DIR, "app_icon_foreground.png"))
    print(f"  -> {ICON_DIR}/app_icon_foreground.png")

    print("Generating splash v2 (1080x1920)...")
    splash = generate_splash_v2()
    splash.save(os.path.join(IMG_DIR, "splash_logo.png"))
    print(f"  -> {IMG_DIR}/splash_logo.png")

    print("Done!")
