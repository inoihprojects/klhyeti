#!/usr/bin/env python3
"""Renders Klhyeti's app icon into assets/icon/.

The icon *is* the calendar: the whole canvas is the page, rather than a
small calendar drawn inside a frame (which reads as a double frame and
shrinks the artwork at small sizes). Platforms apply their own rounding
and masking on top.

Everything is drawn at 4x and downsampled, which is what gives the edges
their smoothness. Run from the repo root:  python3 tool/make_icon.py
"""

import os
from PIL import Image, ImageDraw

S = 1024          # final size
SS = 4            # supersampling factor
N = S * SS

PAPER_TOP = (251, 249, 245)   # #FBF9F5
PAPER_BOTTOM = (237, 232, 222)  # #EDE8DE
INK2 = (90, 85, 76)           # #5A554C
VERMILION = (168, 80, 63)     # #A8503F

# Android crops adaptive icons to a circle/squircle, so anything the mask
# might eat stays outside this fraction of the canvas.
SAFE = 0.66

BAND_BOTTOM = 0.22            # fraction of the canvas the band covers
DOT_RADIUS = 52
DOT_ROWS = (0.44, 0.63, 0.82)  # fractions of canvas height
DOT_COLS = (0.26, 0.5, 0.74)   # fractions of canvas width

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..',
                   'assets', 'icon')


def paper(size: int = S) -> Image.Image:
    """Flat vertical paper gradient — no gloss, no vignette."""
    column = Image.new('RGB', (1, size))
    px = column.load()
    for y in range(size):
        t = y / (size - 1)
        px[0, y] = tuple(
            round(a + (b - a) * t) for a, b in zip(PAPER_TOP, PAPER_BOTTOM)
        )
    return column.resize((size, size), Image.NEAREST)


def draw_band(img: Image.Image, scale: float = 1.0) -> None:
    """The vermilion band across the top, with two binding notches.

    [scale] < 1 composes the design for Android's adaptive icon, where the
    launcher keeps only the middle 66% of the canvas: the band is placed
    at the top of *that* region so it survives the crop, while still
    running the full width so the artwork bleeds past any mask shape.
    """
    d = ImageDraw.Draw(img)
    w, h = img.size
    mid = h / 2
    band_h = h * BAND_BOTTOM * scale
    top = mid - (h / 2) * scale
    # Always full width: a mask crops the sides, it never needs margins.
    d.rectangle([0, top, w, top + band_h], fill=VERMILION)

    # Two notches punched out of the band, like a wall calendar's binding.
    notch_w = w * 0.052 * scale
    notch_h = band_h * 0.42
    notch_y = top + band_h * 0.30
    for cx in (w * 0.33, w * 0.67):
        x = w / 2 + (cx - w / 2) * scale
        d.rounded_rectangle(
            [x - notch_w / 2, notch_y, x + notch_w / 2, notch_y + notch_h],
            radius=notch_w / 2,
            fill=PAPER_TOP,
        )


def draw_dots(img: Image.Image, scale: float = 1.0) -> None:
    """3x3 grid of days; the middle one is "today"."""
    d = ImageDraw.Draw(img)
    w, h = img.size
    r = DOT_RADIUS * (w / S) * scale
    for row, fy in enumerate(DOT_ROWS):
        for col, fx in enumerate(DOT_COLS):
            cx = w / 2 + (w * fx - w / 2) * scale
            cy = h / 2 + (h * fy - h / 2) * scale
            colour = VERMILION if (row == 1 and col == 1) else INK2
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=colour)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)

    # Master: full-bleed page, used for Windows/Linux and as the base.
    master = paper(N).convert('RGBA')
    draw_band(master)
    draw_dots(master)
    master = master.resize((S, S), Image.LANCZOS)
    master.convert('RGB').save(os.path.join(OUT, 'icon.png'))

    # Android adaptive icon. The background layer carries the page and the
    # band so the design still bleeds to the edges under any mask shape;
    # the foreground carries only the dots, which must survive cropping.
    paper(N).resize((S, S), Image.LANCZOS).convert('RGB').save(
        os.path.join(OUT, 'icon_background.png'))

    foreground = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    draw_band(foreground, SAFE)
    draw_dots(foreground, SAFE)
    foreground.resize((S, S), Image.LANCZOS).save(
        os.path.join(OUT, 'icon_foreground.png'))

    # Android 13+ themed icons: one flat silhouette, band included so the
    # shape still reads as a calendar.
    mono_source = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    draw_band(mono_source, SAFE)
    draw_dots(mono_source, SAFE)
    mono = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    mono.paste((0, 0, 0, 255), mask=mono_source.split()[3])
    mono.resize((S, S), Image.LANCZOS).save(
        os.path.join(OUT, 'icon_monochrome.png'))

    print('wrote', ', '.join(sorted(os.listdir(OUT))))


if __name__ == '__main__':
    main()
