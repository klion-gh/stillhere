"""Regenerate every app icon from the source logo.

Run after replacing tools/logo_source.png:

    python tools/make_icons.py

The source already carries an alpha channel, and the icons keep it: no tile,
no plate, just the bird. On Android that means the adaptive icon's background
layer is transparent too, so launchers that mask icons show the artwork
rather than a coloured square.
"""

from __future__ import annotations

import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "tools", "logo_source.png")

ANDROID_RES = os.path.join(ROOT, "client", "android", "app", "src", "main", "res")

# Legacy launcher icon sizes, per density (API < 26).
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

ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]


def trim(im: Image.Image, threshold: int = 8) -> Image.Image:
    """Crops to the visible artwork.

    Thresholded rather than a plain getbbox(): exports often carry a haze of
    almost-transparent pixels out to the canvas edge, and those are enough to
    make getbbox() return the whole image, leaving the logo sitting in a wide
    margin at every icon size.
    """
    mask = im.getchannel("A").point(lambda a: 255 if a > threshold else 0)
    box = mask.getbbox()
    return im.crop(box) if box else im


def square(im: Image.Image, pad: float = 0.0) -> Image.Image:
    """Centre the artwork on a transparent square with optional padding."""
    w, h = im.size
    side = int(max(w, h) * (1 + pad * 2))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(im, ((side - w) // 2, (side - h) // 2), im)
    return canvas


def scaled(art: Image.Image, size: int, fill: float = 1.0) -> Image.Image:
    """Artwork centred on a transparent canvas, covering `fill` of the side."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inner = max(round(size * fill), 1)
    canvas.alpha_composite(
        art.resize((inner, inner), Image.LANCZOS),
        ((size - inner) // 2, (size - inner) // 2),
    )
    return canvas


def write_png(im: Image.Image, *parts: str) -> None:
    path = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, "PNG")
    print("wrote", os.path.relpath(path, ROOT))


def main() -> None:
    art = square(trim(Image.open(SOURCE).convert("RGBA")), pad=0.02)

    # In-app brand mark.
    write_png(art.resize((512, 512), Image.LANCZOS), "client", "assets", "icons", "logo.png")

    # Legacy launcher icon: no mask is applied on API < 26, so the artwork can
    # use the whole canvas.
    for folder, size in LAUNCHER_SIZES.items():
        write_png(scaled(art, size, 0.96), "client", "android", "app", "src", "main", "res", folder, "ic_launcher.png")

    # Adaptive foreground. 0.5 rather than the more generous 66/108 safe zone:
    # the artwork is a square whose corners hold the wing tips, and a circular
    # mask cuts them off at anything larger.
    for folder, size in FOREGROUND_SIZES.items():
        write_png(scaled(art, size, 0.50), "client", "android", "app", "src", "main", "res", folder, "ic_launcher_foreground.png")

    # The splash keeps a filled version — a transparent bitmap over the dark
    # window background is exactly what we want there anyway, so it reuses the
    # adaptive foreground and needs nothing extra.

    # Windows: executable icon, tray icon, installer icon. All transparent.
    # 16px is mush no matter what, but that's inherent to the artwork.
    master = art.resize((256, 256), Image.LANCZOS)
    for path_parts, sizes in (
        (("client", "windows", "runner", "resources", "app_icon.ico"), ICO_SIZES),
        (("client", "assets", "icons", "tray.ico"), [16, 20, 24, 32, 48, 64]),
        (("client", "windows", "installer", "stillhere.ico"), ICO_SIZES),
    ):
        path = os.path.join(ROOT, *path_parts)
        master.save(path, "ICO", sizes=[(s, s) for s in sizes])
        print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
