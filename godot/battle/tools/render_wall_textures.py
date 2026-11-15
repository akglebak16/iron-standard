#!/usr/bin/env python3
"""Renders the siege wall textures (original work, CC0) with the palette of terrain/wall_view.gd.

Usage: python3 render_wall_textures.py <output dir>
Editing the PNGs by hand in an image editor is fine; this script only documents how they were made.
"""
import os
import sys
from PIL import Image, ImageDraw

STONE = "#857a68"
MORTAR = "#554c40"
EDGE = "#2a2219"
PARAPET = "#a49884"
TOWER = "#93876f"
TOWER_INNER = "#6d6252"
GATE_WOOD = "#5b3d22"
GATE_IRON = "#393631"
SS = 4  # supersampling for round shapes


def disc(size, layers):
    big = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    c = size * SS / 2
    for radius, color in layers:
        r = radius * SS
        d.ellipse([c - r, c - r, c + r, c + r], fill=color)
    return big.resize((size, size), Image.LANCZOS)


def main(out):
    os.makedirs(out, exist_ok=True)
    # stone tile: segment width 44 x two courses of 14
    tile = Image.new("RGBA", (44, 28), STONE)
    d = ImageDraw.Draw(tile)
    for row, joint in ((0, 11), (1, 22)):
        y = row * 14
        d.line([(0, y), (43, y)], fill=MORTAR)
        d.line([(joint, y), (joint, y + 13)], fill=MORTAR)
    tile.save(os.path.join(out, "wall_stone.png"))
    # merlon strip: 9x12 block centred in a 22 px pitch
    strip = Image.new("RGBA", (9, 22), (0, 0, 0, 0))
    d = ImageDraw.Draw(strip)
    d.rectangle([0, 5, 8, 16], fill=PARAPET, outline=EDGE)
    strip.save(os.path.join(out, "wall_merlon.png"))
    # towers
    disc(68, [(34, EDGE), (32, TOWER), (22, TOWER_INNER)]).save(os.path.join(out, "wall_tower.png"))
    disc(68, [(34, "#ffffff")]).save(os.path.join(out, "wall_disc.png"))
    # gate leaf 52x14 with hinges at +-15
    leaf = Image.new("RGBA", (52, 14), EDGE)
    d = ImageDraw.Draw(leaf)
    d.rectangle([2, 2, 49, 11], fill=GATE_WOOD)
    for x in (26 - 15, 26 + 15):
        d.rectangle([x, 0, x + 3, 13], fill=GATE_IRON)
    d.rectangle([0, 0, 51, 13], outline=EDGE, width=2)
    leaf.save(os.path.join(out, "wall_gate_leaf.png"))


if __name__ == "__main__":
    main(sys.argv[1])
