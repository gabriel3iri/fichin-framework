"""Cuadros de sentado a partir de la hoja de un personaje (16x32 por cuadro, ver core.save_sheet).

De cada vista quieta (de frente, de espaldas y de perfil) sale una sentada: el cuerpo de la cadera para arriba baja
DROP píxeles (la cadera, a la altura del asiento) y las piernas se rehacen. De frente, las piernas enteras un poco más
cortas (los muslos en escorzo, la rodilla en sombra); de espaldas no se ven (quedan del otro lado del asiento); de
perfil, el muslo horizontal y una canilla de su largo hasta el piso.
El resultado es `<id>_sit.png` (48x32: down, up, side) al lado de `<id>_sheet.png`; CharacterFrames lo carga si está.

    python3 addons/jornada/tools/pixel/sit.py carpeta [carpeta...]   # una _sit.png por cada _sheet.png
"""
import sys
from pathlib import Path

from PIL import Image

W, H = 16, 32
HIP = 22          # fila donde empiezan las piernas (igual en chicos: shrink() quita filas del pecho)
DROP = 2          # cuánto baja el cuerpo al sentarse: la cadera queda a la altura del asiento (SEAT_H de los muebles)
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


def _shade(c: tuple, k: float) -> tuple:
    return tuple(max(0, min(255, int(v * k))) for v in c[:3]) + (c[3],)


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
    """De frente: las piernas enteras pero DROP filas más cortas (los muslos vienen hacia la cámara, en escorzo), con
    la línea de la rodilla en sombra. Así se ve un adulto sentado y no un torso apoyado en los zapatos."""
    out = _body(img)
    legs = img.crop((0, HIP, W, H))                       # 10 filas: pantalón y zapatos
    keep = list(range(legs.height))
    for k in range(DROP):                                 # se quitan filas del medio del pantalón (el escorzo)
        keep.remove(2 + k * 2)
    knee = 2                                              # la rodilla, en la fila donde termina el muslo
    for i, row in enumerate(keep):
        line = legs.crop((0, row, W, row + 1))
        if i < knee:                                      # el muslo, de frente, recibe más luz
            line = Image.eval(line, lambda v: v)
            px = line.load()
            for x in range(W):
                if px[x, 0][3] > 200 and sum(px[x, 0][:3]) > 90:
                    px[x, 0] = _shade(px[x, 0], 1.15)
        elif i == knee:
            px = line.load()
            for x in range(W):
                if px[x, 0][3] > 200 and sum(px[x, 0][:3]) > 90:
                    px[x, 0] = _shade(px[x, 0], 0.7)
        out.alpha_composite(line, (0, HIP + DROP + i))
    return out


def sit_back(img: Image.Image) -> Image.Image:
    """De espaldas: el cuerpo y el asiento del pantalón; las piernas quedan del otro lado, tapadas."""
    out = _body(img)
    out.alpha_composite(img.crop((0, HIP, W, HIP + 2)), (0, HIP + DROP))
    return out


def sit_side(img: Image.Image, ink: tuple) -> Image.Image:
    """Mirando a la derecha: el muslo horizontal a la altura de la cadera, la rodilla adelante y la canilla hasta el
    piso, del largo de una canilla de verdad (el asiento está a SEAT_H px: la canilla lo cubre entera)."""
    out = _body(img)
    pants = _color(img, [(6, 25), (7, 25), (8, 26), (6, 27), (9, 26)], (60, 60, 70, 255))
    shoe = _color(img, [(9, 30), (9, 29), (8, 29), (10, 29), (6, 29)], (40, 30, 25, 255))
    dark = _shade(pants, 0.75)
    light = _shade(pants, 1.12)
    hip_y = HIP + DROP                 # primera fila debajo del cuerpo
    for x in range(4, 13):             # muslo: dos filas, la de arriba con luz
        out.putpixel((x, hip_y - 1), light if x > 6 else pants)
        out.putpixel((x, hip_y), pants if x < 11 else dark)
    for y in range(hip_y + 1, H - 2):  # canilla, de la rodilla al piso
        out.putpixel((11, y), pants)
        out.putpixel((12, y), dark)
    for x in range(11, 15):            # zapato, con la punta adelante
        out.putpixel((x, H - 2), shoe)
        out.putpixel((x, H - 1), _shade(shoe, 0.8))
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
