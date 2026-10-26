"""Piel por defecto de la UI del framework (addons/jornada/ui/skin): tecla [E], reloj, flecha, marco y ojo.
Uso: python3 addons/jornada/tools/pixel/skin.py   (o pixel.skin.write(carpeta) desde otro generador)
"""
import math
import sys
from pathlib import Path

from PIL import Image

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from pixel.core import C, T, px_grid

SKIN_DIR = Path(__file__).resolve().parents[2] / "ui" / "skin"


def ui_key_e() -> Image.Image:
    """Tecla [E] para el aviso de interacción."""
    img = Image.new("RGBA", (13, 14), T)
    for y in range(13):
        for x in range(13):
            if (x, y) in ((0, 0), (12, 0)):
                continue
            edge = x in (0, 12) or y in (0, 12)
            col = C["ink"] if edge else (C["ash4"] if y >= 10 else C["wht"])
            img.putpixel((x, y), col)
    for x in range(2, 11):                             # sombra bajo la tecla
        img.putpixel((x, 13), C["ink"])
    glyph = ["XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "XXXXX"]
    for dy, row in enumerate(glyph):
        for dx, ch in enumerate(row):
            if ch == "X":
                img.putpixel((4 + dx, 2 + dy), C["ink"])
    return img



def ui_watch() -> Image.Image:
    """Reloj de bolsillo 36x40: aro, caja de latón, esfera marfil con las 12 marcas.
    Las agujas se dibujan en el juego (pixel a pixel) para que marquen la hora real."""
    w, h, cx, cy, r = 36, 40, 18.0, 22.0, 16.2
    img = Image.new("RGBA", (w, h), T)
    for y in range(h):
        for x in range(w):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            d = math.hypot(dx, dy)
            if d > r:
                continue
            if d > r - 1.0:
                col = C["ink"]
            elif d > r - 3.0:
                light = (dx + dy) < 0             # luz desde arriba a la izquierda
                col = C["yel0"] if light else C["rus1"]
                if d > r - 1.9:
                    col = C["yel1"] if light else C["rus0"]
            else:
                col = C["wht"]
            img.putpixel((x, y), col)
    for i in range(12):                           # marcas de hora
        a = math.radians(i * 30)
        long_tick = i % 3 == 0
        for rad in ((10.5, 11.5, 12.5) if long_tick else (12.0, 12.5)):
            px = int(round(cx + math.sin(a) * rad - 0.5))
            py = int(round(cy - math.cos(a) * rad - 0.5))
            img.putpixel((px, py), C["ink"])
    for y in range(0, 5):                         # aro y corona
        for x in range(14, 22):
            edge = y in (0, 4) or x in (14, 21)
            if (x in (14, 21) and y in (0, 4)) or (y == 4 and x in (15, 20)) and False:
                continue
            if y < 5 and not (y == 4 and 16 <= x <= 19) or (y == 4):
                img.putpixel((x, y), C["ink"] if edge else T)
    for x in range(16, 20):
        for y in (4, 5):
            img.putpixel((x, y), C["yel0"])
    return img

def ui_arrow() -> Image.Image:
    img = Image.new("RGBA", (7, 4), T)
    for y, row in enumerate(["XXXXXXX", ".XXXXX.", "..XXX..", "...X..."]):
        for x, ch in enumerate(row):
            if ch == "X":
                img.putpixel((x, y), C["yel1"])
    return img


def ui_panel() -> Image.Image:
    """Marco 9-slice (márgenes de 4 px) para cajas de diálogo y placas de nombre."""
    img = Image.new("RGBA", (16, 16), T)
    for y in range(16):
        for x in range(16):
            d = min(x, y, 15 - x, 15 - y)
            if d == 0 and x in (0, 15) and y in (0, 15):
                continue                                # esquinas redondeadas
            if d == 0:
                col = C["ink"]
            elif d == 1:
                col = C["yel0"] if y == 1 else C["rus2"]
            elif d == 2:
                col = C["rus0"]
            else:
                col = (0x23, 0x23, 0x23, 245)
            img.putpixel((x, y), col)
    for x, y in ((3, 3), (12, 3), (3, 12), (12, 12)):   # remaches de las esquinas
        img.putpixel((x, y), C["rus1"])
    return img


def ui_eye() -> Image.Image:
    legend = {"O": C["ink"], "w": C["wht"], "p": C["ink"], "h": C["wht"]}
    rows = [
        "...OOOOO...",
        ".OOwwwwwOO.",
        "OwwwpppwwwO",
        "OwwwphpwwwO",
        "OwwwpppwwwO",
        ".OOwwwwwOO.",
        "...OOOOO...",
    ]
    return px_grid(rows, legend)


def write(out: Path = SKIN_DIR) -> None:
    out.mkdir(parents=True, exist_ok=True)
    for name, img in {"ui_key_e": ui_key_e(), "ui_arrow": ui_arrow(), "ui_panel": ui_panel(), "ui_eye": ui_eye(),
                      "ui_watch": ui_watch()}.items():
        img.save(out / f"{name}.png")


if __name__ == "__main__":
    write()
