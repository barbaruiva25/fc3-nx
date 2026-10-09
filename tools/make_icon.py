#!/usr/bin/env python3
"""Writes app/icon.jpg: the 256x256 JPEG the homebrew menu shows (rexglue_switch_add_nro, app/CMakeLists.txt).

This is a neutral placeholder, not artwork: the one that came with sa2-nx was Sonic Adventure 2's logo, which would
have shown that game's art in this port's menu entry. Replace it with a real icon when there is one; the only
requirement is a 256x256 JPEG at this path.

    python3 tools/make_icon.py
"""

import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'app', 'icon.jpg')
SIZE = 256

# Far Cry 3's palette is jungle green over a dark sky, and the islands are Pacific. Not the game's art, only a
# recognisable placeholder that is not another game's.
TOP = (18, 32, 26)
BOTTOM = (58, 92, 44)
LEAF = (96, 142, 58)
LEAF_DARK = (58, 92, 34)
WATER = (34, 78, 96)


def draw():
    img = Image.new('RGB', (SIZE, SIZE), TOP)
    d = ImageDraw.Draw(img)

    # Vertical gradient sky.
    for y in range(SIZE):
        t = y / (SIZE - 1)
        d.line([(0, y), (SIZE, y)],
               fill=(round(TOP[0] + (BOTTOM[0] - TOP[0]) * t),
                     round(TOP[1] + (BOTTOM[1] - TOP[1]) * t),
                     round(TOP[2] + (BOTTOM[2] - TOP[2]) * t)))

    # Sea along the bottom.
    d.rectangle([0, 196, SIZE, SIZE], fill=WATER)

    # Two island ridges behind, one in front: the silhouette of a Far Cry island.
    d.polygon([(0, 196), (46, 150), (86, 172), (128, 132), (176, 168), (216, 146), (256, 194)],
              fill=LEAF_DARK)
    d.polygon([(0, 196), (58, 168), (112, 188), (168, 162), (214, 186), (256, 172), (256, 196)],
              fill=LEAF)

    # A palm silhouette on the front ridge.
    d.line([(150, 168), (146, 118)], fill=(28, 40, 24), width=6)
    for dx, dy in ((-34, 14), (-30, -6), (2, -18), (30, -8), (34, 12)):
        d.line([(146, 118), (146 + dx, 118 + dy)], fill=LEAF, width=9)

    # "FC3" over the sky, so the menu entry is identifiable at a glance.
    d.text((SIZE // 2, 34), 'FC3', fill=(238, 238, 230), anchor='mm',
           font_size=64)

    return img


def main():
    img = draw()
    img.save(OUT, 'JPEG', quality=92)
    print(f'wrote {OUT} ({img.size[0]}x{img.size[1]} JPEG)')


if __name__ == '__main__':
    main()