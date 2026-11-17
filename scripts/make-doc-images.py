#!/usr/bin/env python3
"""Génère les visuels du README (banner, états, aperçu du menu)."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
IMAGES = ROOT / "docs" / "images"
IMAGES.mkdir(parents=True, exist_ok=True)

FONT_REGULAR = "/System/Library/Fonts/HelveticaNeue.ttc"
FONT_BOLD = "/System/Library/Fonts/HelveticaNeue.ttc"

def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_BOLD if bold else FONT_REGULAR, size, index=1 if bold else 0)


def vertical_gradient(size, top, bottom):
    image = Image.new("RGB", size, top)
    draw = ImageDraw.Draw(image)
    for y in range(size[1]):
        t = y / max(1, size[1] - 1)
        color = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
        draw.line([(0, y), (size[0], y)], fill=color)
    return image


def add_glow(image, center, radius, color, blur=90):
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.ellipse(
        [center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius],
        fill=color,
    )
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    image.alpha_composite(layer)


def rounded_shadow(image, box, radius, blur=18, offset=12, alpha=150):
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    x0, y0, x1, y1 = box
    draw.rounded_rectangle(
        [x0, y0 + offset, x1, y1 + offset],
        radius=radius,
        fill=(0, 0, 0, alpha),
    )
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    image.alpha_composite(layer)


def paste_icon(canvas, filename, box):
    icon = Image.open(IMAGES / filename).convert("RGBA")
    icon = icon.resize((box[2] - box[0], box[3] - box[1]), Image.LANCZOS)
    canvas.alpha_composite(icon, (box[0], box[1]))


def make_banner():
    width, height = 1600, 500
    image = vertical_gradient((width, height), (10, 12, 17), (22, 28, 38)).convert("RGBA")
    add_glow(image, (220, 160), 330, (34, 197, 94, 45), blur=110)

    paste_icon(image, "icon-green.png", (90, 160, 270, 340))

    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle([330, 132, 342, 360], radius=6, fill=(52, 211, 153, 255))
    draw.text((378, 120), "MacServer", font=font(118, True), fill=(245, 247, 250))
    draw.text(
        (382, 262),
        "Transforme ton MacBook en serveur, uniquement sur secteur.",
        font=font(31),
        fill=(170, 178, 192),
    )
    draw.text(
        (382, 316),
        "macOS 13+  ·  Universal  ·  Open source",
        font=font(23),
        fill=(110, 231, 160),
    )

    pill = [382, 370, 532, 414]
    draw.rounded_rectangle(pill, radius=22, fill=(34, 197, 94, 30), outline=(52, 211, 153, 190))
    draw.text((404, 380), "v1.0.0", font=font(21, True), fill=(134, 239, 172))

    image.convert("RGB").save(IMAGES / "banner.png", optimize=True)
    print("banner.png")


def make_icon_states():
    width, height = 1600, 460
    image = vertical_gradient((width, height), (10, 12, 17), (24, 30, 40)).convert("RGBA")
    add_glow(image, (250, 120), 320, (34, 197, 94, 35), blur=120)
    add_glow(image, (1350, 380), 300, (249, 115, 22, 30), blur=120)

    draw = ImageDraw.Draw(image)
    draw.text((80, 50), "Les 3 modes + l'alerte", font=font(42, True), fill=(245, 247, 250))
    draw.text(
        (80, 108),
        "L'icône indique toujours l'état, sans ouvrir le menu.",
        font=font(22),
        fill=(160, 168, 182),
    )

    states = [
        ("icon-green.png", "Serveur secteur", "Veille désactivée"),
        ("icon-pause.png", "Portable / pause", "Veille normale"),
        ("icon-battery.png", "Serveur batterie", "Jusqu'à 20 %"),
        ("icon-error.png", "Alerte", "Service arrêté"),
    ]

    centers = [260, 620, 980, 1340]
    for (filename, label, sublabel), center in zip(states, centers):
        paste_icon(image, filename, (center - 80, 180, center + 80, 340))
        draw.text((center, 370), label, font=font(27, True), fill=(245, 247, 250), anchor="ma")
        draw.text((center, 408), sublabel, font=font(19), fill=(150, 158, 172), anchor="ma")

    image.convert("RGB").save(IMAGES / "icon-states.png", optimize=True)
    print("icon-states.png")


def make_menu_preview():
    width, height = 1000, 640
    image = vertical_gradient((width, height), (12, 14, 19), (26, 32, 43)).convert("RGBA")
    add_glow(image, (780, 120), 300, (34, 197, 94, 32), blur=100)

    draw = ImageDraw.Draw(image)

    # Barre des menus simplifiée.
    draw.rectangle([0, 0, width, 54], fill=(8, 10, 14, 210))
    draw.line([0, 54, width, 54], fill=(70, 76, 88, 220), width=1)
    paste_icon(image, "icon-green.png", (700, 13, 728, 41))
    draw.text((820, 17), "Tue 17 Nov   22:00", font=font(16), fill=(225, 229, 236))

    # Panneau du menu.
    panel = [558, 54, 958, 474]
    rounded_shadow(image, panel, radius=16, blur=20, offset=14, alpha=160)
    draw.rounded_rectangle(panel, radius=16, fill=(31, 32, 35, 250), outline=(70, 72, 78, 255), width=1)

    x = 580
    draw.text((x, 76), "MacServer — Actif — secteur", font=font(20, True), fill=(245, 247, 250))
    draw.text(
        (x, 108),
        "Le Mac reste éveillé, capot ouvert ou fermé.",
        font=font(15),
        fill=(158, 164, 176),
    )

    def separator(y):
        draw.line([x, y, 936, y], fill=(66, 68, 74), width=1)

    separator(144)
    draw.text((x, 162), "Mettre en pause", font=font(18), fill=(240, 242, 246))
    draw.text(
        (x, 202),
        "Rester éveillé sur batterie (max 20 %)",
        font=font(18),
        fill=(240, 242, 246),
    )
    separator(244)

    draw.text((x, 264), "Verrouiller l'écran maintenant", font=font(18), fill=(240, 242, 246))
    draw.text((x, 304), "Ouvrir le journal", font=font(18), fill=(240, 242, 246))
    draw.text((x, 344), "Désinstaller MacServer…", font=font(18), fill=(240, 242, 246))
    separator(386)
    draw.text(
        (x, 404),
        "Quitter l'icône (le service continue)",
        font=font(18),
        fill=(240, 242, 246),
    )

    image.convert("RGB").save(IMAGES / "menu-preview.png", optimize=True)
    print("menu-preview.png")


def make_social_preview():
    source = Image.open(IMAGES / "banner.png").convert("RGB")
    # Format 1280x640 : on centre le banner et on complète avec le fond.
    canvas = vertical_gradient((1280, 640), (10, 12, 17), (22, 28, 38)).convert("RGBA")
    add_glow(canvas, (240, 180), 320, (34, 197, 94, 40), blur=110)
    paste_icon(canvas, "icon-green.png", (90, 220, 250, 380))
    draw = ImageDraw.Draw(canvas)
    draw.text((300, 200), "MacServer", font=font(100, True), fill=(245, 247, 250))
    draw.text(
        (304, 330),
        "MacBook as a server,\nonly when plugged in.",
        font=font(34),
        fill=(170, 178, 192),
        spacing=8,
    )
    draw.text(
        (304, 450),
        "macOS 13+  ·  Universal  ·  Open source",
        font=font(22),
        fill=(110, 231, 160),
    )
    canvas.convert("RGB").save(IMAGES / "social-preview.png", optimize=True)
    print("social-preview.png")


if __name__ == "__main__":
    make_banner()
    make_icon_states()
    make_menu_preview()
    make_social_preview()
