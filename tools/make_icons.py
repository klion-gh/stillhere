"""Regenerate every app icon from the source logo.

Run after replacing tools/logo_source.png:

    python tools/make_icons.py

The source is a bird on a flat white background, so the first step is
cutting that background out. A plain "white becomes transparent" rule would
also eat the highlights on the bird's back, so instead we flood-fill from the
border: only white that is connected to the edge is background.
"""

from __future__ import annotations

import os
from collections import deque

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "tools", "logo_source.png")

# Midnight palette, so the icon matches the app's default look.
BG_TOP = (28, 22, 48)
BG_BOTTOM = (14, 11, 24)

ANDROID_RES = os.path.join(ROOT, "client", "android", "app", "src", "main", "res")
# Legacy launcher icon sizes, per density.
LAUNCHER_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
# Adaptive icons are drawn at 108dp with only the middle 72dp guaranteed
# visible, so the foreground layer is larger than the legacy icon.
FOREGROUND_SIZES = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}


def cut_background(im: Image.Image) -> Image.Image:
    """Make the edge-connected white area transparent."""
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()

    def is_bg(x: int, y: int) -> bool:
        r, g, b, a = px[x, y]
        return a > 0 and r > 235 and g > 235 and b > 235

    mask = bytearray(w * h)
    queue = deque()
    for x in range(w):
        for y in (0, h - 1):
            if is_bg(x, y) and not mask[y * w + x]:
                mask[y * w + x] = 1
                queue.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if is_bg(x, y) and not mask[y * w + x]:
                mask[y * w + x] = 1
                queue.append((x, y))

    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and not mask[ny * w + nx] and is_bg(nx, ny):
                mask[ny * w + nx] = 1
                queue.append((nx, ny))

    alpha = Image.frombytes("L", (w, h), bytes(255 - v * 255 for v in mask))
    # The cut is binary, which leaves a hard staircase edge. A sub-pixel blur
    # softens it enough that downscaling doesn't alias.
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.8))
    im.putalpha(alpha)
    return im


def trim(im: Image.Image) -> Image.Image:
    box = im.getchannel("A").getbbox()
    return im.crop(box) if box else im


def square(im: Image.Image, pad: float = 0.0) -> Image.Image:
    """Centre the artwork on a transparent square with optional padding."""
    w, h = im.size
    side = int(max(w, h) * (1 + pad * 2))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(im, ((side - w) // 2, (side - h) // 2), im)
    return canvas


def gradient(size: int) -> Image.Image:
    bg = Image.new("RGB", (1, size))
    draw = ImageDraw.Draw(bg)
    for y in range(size):
        t = y / max(size - 1, 1)
        draw.point(
            (0, y),
            fill=tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)),
        )
    return bg.resize((size, size), Image.NEAREST).convert("RGBA")


def rounded_tile(art: Image.Image, size: int, radius_ratio: float = 0.22) -> Image.Image:
    """Logo on the app's dark gradient, rounded like the in-app brand mark."""
    tile = gradient(size)
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size * 4 - 1, size * 4 - 1),
        radius=int(size * 4 * radius_ratio),
        fill=255,
    )
    tile.putalpha(mask.resize((size, size), Image.LANCZOS))

    inner = round(size * 0.78)
    scaled = art.resize((inner, inner), Image.LANCZOS)
    tile.alpha_composite(scaled, ((size - inner) // 2, (size - inner) // 2))
    return tile


def write_png(im: Image.Image, *parts: str) -> None:
    path = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, "PNG")
    print("wrote", os.path.relpath(path, ROOT))


def main() -> None:
    art = square(trim(cut_background(Image.open(SOURCE))), pad=0.02)

    # In-app brand mark: the bird alone, on transparency.
    write_png(art.resize((512, 512), Image.LANCZOS), "client", "assets", "icons", "logo.png")

    for folder, size in LAUNCHER_SIZES.items():
        write_png(rounded_tile(art, size), "client", "android", "app", "src", "main", "res", folder, "ic_launcher.png")

    # Adaptive foreground: transparent, and inset so the launcher's mask
    # (circle, squircle, …) never clips the wings.
    for folder, size in FOREGROUND_SIZES.items():
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        # 0.5 rather than the more generous 66/108 safe zone: the artwork is a
        # square whose corners hold the wing tips, and a circular mask cuts
        # them off at anything larger.
        inner = round(size * 0.50)
        canvas.alpha_composite(art.resize((inner, inner), Image.LANCZOS), ((size - inner) // 2, (size - inner) // 2))
        write_png(canvas, "client", "android", "app", "src", "main", "res", folder, "ic_launcher_foreground.png")

    # Windows executable icon and tray icon. Below ~24px the bird turns to
    # mush, so the tray gets the same tile rather than bare artwork.
    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    tile256 = rounded_tile(art, 256)
    ico_path = os.path.join(ROOT, "client", "windows", "runner", "resources", "app_icon.ico")
    tile256.save(ico_path, "ICO", sizes=[(s, s) for s in ico_sizes])
    print("wrote", os.path.relpath(ico_path, ROOT))

    tray_path = os.path.join(ROOT, "client", "assets", "icons", "tray.ico")
    tile256.save(tray_path, "ICO", sizes=[(s, s) for s in (16, 20, 24, 32, 48, 64)])
    print("wrote", os.path.relpath(tray_path, ROOT))

    # Inno Setup wants a real .ico for the installer wizard.
    installer_path = os.path.join(ROOT, "client", "windows", "installer", "stillhere.ico")
    tile256.save(installer_path, "ICO", sizes=[(s, s) for s in ico_sizes])
    print("wrote", os.path.relpath(installer_path, ROOT))


if __name__ == "__main__":
    main()
