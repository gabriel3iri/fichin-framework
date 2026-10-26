#!/usr/bin/env python3
"""Arte del ejemplo con la librería del framework (addons/jornada/tools/pixel): tiles, objetos y personajes.
La piel de la UI viene con el framework (addons/jornada/ui/skin).

Uso (desde examples/primer_dia): python3 tools/make_art.py
Después: godot --headless --path . --import  y  godot --headless --path . res://addons/jornada/tools/build_world.tscn
"""
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "addons/jornada/tools"))
from pixel.core import C, T, Canvas, hexc, noise, save_sheet  # noqa: E402
from pixel.figures import build_frames, portrait  # noqa: E402

ART = ROOT / "assets/generated_assets"
TILES = ART / "tiles/base"
PROPS = ART / "props"

# Cómo se ve cada uno (vocabulario en addons/jornada/tools/pixel/figures.py).
CAST = {
    "protagonist": dict(body="male", garment="apron", coat="#6A6F7A", pants="#3A3530", shirt="#E4E2D4",
                        apron="#E9E6DA", hat="flat_cap", hat_color="#4A3A2C", hair="short", hair_color="#3B2A1E",
                        skin="fair", bg="#5A6A78", age=17, runs=True),
    "marta": dict(body="female", build="stout", garment="dress", coat="#7A4A3A", pants="#3A2A20", shirt="#E4E2D4",
                  apron="#E9E6DA", hair="bun", hair_color="#8A8A8A", skin="ruddy", extras=["shawl"], bg="#7A5A44",
                  age=58),
    "tomas": dict(body="male", build="thin", garment="jacket", coat="#2F4A6A", pants="#262B36", shirt="#D8D4C4",
                  hat="kepi", hat_color="#24364F", hair="short", hair_color="#2B1F18", skin="fair",
                  extras=["mustache", "bag", "badge"], bg="#3C5878", age=44),
    "lucia": dict(body="female", garment="dress", coat="#A0503A", pants="#3A2A20", shirt="#E4E2D4", hair="braids",
                  hair_color="#6B3B22", skin="fair", bg="#6A7A50", age=9, kid=4),
}


def textured(base: str, dark: str, light: str, salt: int, density: int = 40) -> Image.Image:
    """Tile de 16x16 con motas claras y oscuras (ruido determinista, empalma consigo mismo)."""
    img = Image.new("RGBA", (16, 16), hexc(base))
    for y in range(16):
        for x in range(16):
            n = noise(x, y, salt)
            if n < density:
                img.putpixel((x, y), hexc(dark))
            elif n > 255 - density // 2:
                img.putpixel((x, y), hexc(light))
    return img


def bricks(base: str, mortar: str, salt: int) -> Image.Image:
    img = textured(base, mortar, base, salt, 18)
    for y in range(16):
        for x in range(16):
            row = y // 4
            if y % 4 == 3 or (x + (4 if row % 2 else 0)) % 8 == 7:
                img.putpixel((x, y), hexc(mortar))
    return img


def planks(base: str, seam: str, salt: int) -> Image.Image:
    img = textured(base, seam, base, salt, 14)
    for y in range(16):
        for x in range(16):
            if y % 4 == 3 or (x + y // 4 * 5) % 16 == 0:
                img.putpixel((x, y), hexc(seam))
    return img


def roof(top: bool) -> Image.Image:
    img = Image.new("RGBA", (16, 16), hexc("#8A3A2C"))
    for y in range(16):
        for x in range(16):
            if y % 4 == 3:
                img.putpixel((x, y), hexc("#5E2A20"))
            elif (x + (y // 4) * 2) % 6 == 0:
                img.putpixel((x, y), hexc("#A84A36"))
    if top:
        for x in range(16):
            img.putpixel((x, 0), C["ink"])
    return img


def window(wall: Image.Image) -> Image.Image:
    img = wall.copy()
    for y in range(3, 13):
        for x in range(3, 13):
            edge = x in (3, 12) or y in (3, 12)
            img.putpixel((x, y), hexc("#3A2A20") if edge else hexc("#FFCD9C") if (x + y) % 5 else hexc("#FFE6C7"))
    for x in range(4, 12):
        img.putpixel((x, 8), hexc("#3A2A20"))
    return img


def door(w: int) -> Image.Image:
    """Puerta de 2x3 tiles (32x48) para cortar en seis."""
    img = Image.new("RGBA", (32, 48), hexc("#6E4A2E"))
    for y in range(48):
        for x in range(32):
            if x in (0, 31) or y == 0:
                img.putpixel((x, y), C["ink"])
            elif x in (1, 30) or y == 1:
                img.putpixel((x, y), hexc("#4E3320"))
            elif x == 15 or x == 16:
                img.putpixel((x, y), hexc("#4E3320"))
            elif (x % 5 == 0) and y > 3:
                img.putpixel((x, y), hexc("#5E3E25"))
    for y in (24, 25):
        for x in (12, 19):
            img.putpixel((x, y), hexc("#C9A04A"))
    return img


def window_2x2(wall: Image.Image) -> dict:
    big = Image.new("RGBA", (32, 32))
    for ox in (0, 16):
        for oy in (0, 16):
            big.paste(wall, (ox, oy))
    for y in range(4, 30):
        for x in range(5, 27):
            edge = x in (5, 26) or y in (4, 29) or x == 16 or y == 17
            big.putpixel((x, y), hexc("#3A2A20") if edge else hexc("#FFCD9C") if (x * 3 + y) % 7 else hexc("#FFE6C7"))
    return {part: big.crop((ox, oy, ox + 16, oy + 16)) for part, (ox, oy) in
            {"tl": (0, 0), "tr": (16, 0), "bl": (0, 16), "br": (16, 16)}.items()}


def mat() -> Image.Image:
    img = textured("#7A4A3A", "#5E3A2A", "#9A6A52", 9, 50)
    for x in range(16):
        img.putpixel((x, 0), hexc("#4E3320"))
        img.putpixel((x, 15), hexc("#4E3320"))
    return img


def counter() -> Image.Image:
    img = planks("#9A6A42", "#5E3E25", 11)
    for x in range(16):
        for y in range(0, 4):
            img.putpixel((x, y), hexc("#D9B88A") if y else C["ink"])
    return img


def prop(rows: list[str], legend: dict) -> Image.Image:
    cv = Canvas(len(rows[0]), len(rows))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != ".":
                cv.px(x, y, ch)
    cv.outline()
    return cv.image({**legend, "O": C["ink"]})


WOOD = {"w": hexc("#9A6A42"), "d": hexc("#5E3E25"), "l": hexc("#C08A58")}


def props() -> dict:
    bench = prop(["............................",
                  "wwwwwwwwwwwwwwwwwwwwwwwwwwww",
                  "llllllllllllllllllllllllllll",
                  "dddddddddddddddddddddddddddd",
                  ".d.......................d..",
                  ".d.......................d.."], WOOD)
    table = prop(["llllllllllllllllllllllll",
                  "wwwwwwwwwwwwwwwwwwwwwwww",
                  "dddddddddddddddddddddddd",
                  ".d....................d.",
                  ".d....................d.",
                  ".d....................d."], WOOD)
    sacks = prop(["..ssss....",
                  ".ssssss...",
                  "sssssssss.",
                  "shsssssss.",
                  "ssssssshss",
                  "ssssssssss",
                  ".ssssssss."], {"s": hexc("#C8B48A"), "h": hexc("#E4D4AA")})
    oven = prop(["....bbbbbbbbbbbb....",
                 "..bbbbbbbbbbbbbbbb..",
                 ".bbbbbbbbbbbbbbbbbb.",
                 "bbbbbbbbbbbbbbbbbbbb",
                 "bbbbbbkkkkkkkkbbbbbb",
                 "bbbbbkkffffffkkbbbbb",
                 "bbbbbkffyyyyffkbbbbb",
                 "bbbbbkfyyyyyyfkbbbbb",
                 "bbbbbbbbbbbbbbbbbbbb",
                 "gggggggggggggggggggg"],
                {"b": hexc("#9A5A42"), "k": C["ink"], "f": hexc("#D9603A"), "y": hexc("#FFCD9C"), "g": hexc("#666655")})
    flowers = prop(["..r..y..",
                    ".rrryyy.",
                    "..g..g..",
                    "pppppppp",
                    "pppppppp"], {"r": hexc("#C04A4A"), "y": hexc("#E8C860"), "g": hexc("#4F7358"), "p": hexc("#8A5A3A")})
    tree = Image.new("RGBA", (24, 36), T)
    for y in range(36):
        for x in range(24):
            dx, dy = x - 12, y - 13
            if dx * dx + dy * dy * 1.3 < 110:
                n = noise(x, y, 5)
                tree.putpixel((x, y), hexc("#2D4836") if n < 80 else hexc("#4F7358") if n > 200 else hexc("#355541"))
            elif 10 <= x <= 13 and y >= 22:
                tree.putpixel((x, y), hexc("#5A3B25"))
    return {"bench": bench, "table": table, "sacks": sacks, "oven": oven, "flowers": flowers, "tree": tree}


def main() -> None:
    TILES.mkdir(parents=True, exist_ok=True)
    PROPS.mkdir(parents=True, exist_ok=True)
    wall = bricks("#B8A48A", "#7A6A58", 3)
    tiles = {
        "grass": textured("#4F7358", "#355541", "#6A8660", 1),
        "dirt": textured("#86593A", "#5F3F26", "#9A6A42", 2),
        "cobble": bricks("#85856F", "#4F4F44", 4),
        "hedge": textured("#243A2C", "#16271E", "#355541", 6, 70),
        "wall": wall,
        "window": window(wall),
        "roof_a": roof(True),
        "roof_b": roof(False),
        "plinth": bricks("#666655", "#3B3B33", 7),
        "floor": planks("#B88A58", "#7A5434", 8),
        "mat": mat(),
        "counter": counter(),
    }
    out_door = door(2)
    for prefix in ("door", "door_in"):
        for name, (x, y) in {"tl": (0, 0), "tr": (16, 0), "ml": (0, 16), "mr": (16, 16), "bl": (0, 32),
                             "br": (16, 32)}.items():
            tiles[f"{prefix}_{name}"] = out_door.crop((x, y, x + 16, y + 16))
    for part, img in window_2x2(wall).items():
        tiles[f"win_{part}"] = img
    for name, img in tiles.items():
        img.save(TILES / f"{name}.png")
    for name, img in props().items():
        img.save(PROPS / f"{name}.png")
    sprites = ART / "sprites"
    (sprites / "npcs").mkdir(parents=True, exist_ok=True)
    (ART / "portraits").mkdir(parents=True, exist_ok=True)
    for name, d in CAST.items():
        frames = build_frames(d)
        save_sheet(frames, sprites / ("protagonist_sheet.png" if name == "protagonist" else f"npcs/{name}_sheet.png"))
        if name != "protagonist":
            portrait(d, seed=name).save(ART / "portraits" / f"{name}.png")
    print(f"{len(tiles)} tiles, {len(props())} objetos, {len(CAST)} personajes")


if __name__ == "__main__":
    main()
