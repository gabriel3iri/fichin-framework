"""Cuadros de sentado a partir de la hoja de un personaje (16x32 por cuadro, ver core.save_sheet).

De cada vista quieta (de frente, de espaldas y de perfil) sale una sentada: el cuerpo de la cadera para arriba baja
DROP píxeles y las piernas se rehacen. De frente se ven las canillas y los zapatos (los muslos van hacia la cámara);
de espaldas no se ven (quedan del otro lado del asiento); de perfil, el muslo horizontal y la canilla hacia el piso.
El resultado es `<id>_sit.png` (48x32: down, up, side) al lado de `<id>_sheet.png`; CharacterFrames lo carga si está.

    python3 addons/jornada/tools/pixel/sit.py carpeta [carpeta...]   # una _sit.png por cada _sheet.png
"""
import sys
from pathlib import Path

from PIL import Image

W, H = 16, 32
HIP = 22          # fila donde empiezan las piernas (igual en chicos: shrink() quita filas del pecho)
DROP = 5          # cuánto baja el cuerpo al sentarse
FEET = 27         # de frente, de acá para abajo quedan las canillas y los zapatos
T = (0, 0, 0, 0)


def _frame(sheet: Image.Image, index: int) -> Image.Image:
    return sheet.crop((index * W, 0, index * W + W, H))


def _body(img: Image.Image) -> Image.Image:
    out = Image.new("RGBA", (W, H), T)
    out.paste(img.crop((0, 0, W, HIP)), (0, DROP))
    return out


def _color(img: Image.Image, spots: list, fallback: tuple) -> tuple:
    """El primer color opaco y no de contorno (no casi negro) entre `spots`."""
    for x, y in spots:
        c = img.getpixel((x, y))
        if c[3] > 200 and sum(c[:3]) > 90:
            return c
    return fallback


def _outline(img: Image.Image, ink: tuple) -> None:
    src = img.copy()
    for y in range(H):
        for x in range(W):
            if src.getpixel((x, y))[3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and src.getpixel((nx, ny))[3] > 200:
                    img.putpixel((x, y), ink)
                    break


def sit_front(img: Image.Image) -> Image.Image:
    out = _body(img)
    legs = img.crop((0, FEET, W, H))
    out.alpha_composite(legs, (0, FEET))   # canillas y zapatos donde estaban
    return out


def sit_back(img: Image.Image) -> Image.Image:
    return _body(img)


def sit_side(img: Image.Image, ink: tuple) -> Image.Image:
    """Mirando a la derecha: muslo hacia adelante a la altura de la cadera bajada, canilla al piso."""
    out = _body(img)
    pants = _color(img, [(6, 25), (7, 25), (8, 26), (6, 27), (9, 26)], (60, 60, 70, 255))
    shoe = _color(img, [(9, 29), (8, 29), (10, 29), (6, 29)], (40, 30, 25, 255))
    dark = tuple(max(0, int(v * 0.75)) for v in pants[:3]) + (255,)
    hip_y = HIP + DROP - 1
    for x in range(5, 12):             # muslo
        out.putpixel((x, hip_y - 1), pants)
        out.putpixel((x, hip_y), dark if x < 7 else pants)
    for y in range(hip_y + 1, 29):     # canilla
        out.putpixel((10, y), pants)
        out.putpixel((11, y), dark)
    for x in range(10, 14):            # zapato
        out.putpixel((x, 29), shoe)
        out.putpixel((x, 30), shoe)
    _outline(out, ink)
    return out


def sit_sheet(sheet: Image.Image) -> Image.Image:
    sheet = sheet.convert("RGBA")
    down, up, side = _frame(sheet, 0), _frame(sheet, 5), _frame(sheet, 10)
    ink = _color(side, [], (20, 16, 14, 255))
    for y in range(H):                 # el contorno que ya usa el personaje
        for x in range(W):
            c = side.getpixel((x, y))
            if c[3] > 200 and sum(c[:3]) < 90:
                ink = c
                break
        else:
            continue
        break
    out = Image.new("RGBA", (W * 3, H), T)
    for i, img in enumerate((sit_front(down), sit_back(up), sit_side(side, ink))):
        out.paste(img, (i * W, 0))
    return out


def write_for(folder: Path) -> int:
    count = 0
    for path in sorted(folder.glob("*_sheet.png")):
        sit_sheet(Image.open(path)).save(path.with_name(path.name.replace("_sheet.png", "_sit.png")))
        count += 1
    return count


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        print(f"{arg}: {write_for(Path(arg))} hojas de sentado")
