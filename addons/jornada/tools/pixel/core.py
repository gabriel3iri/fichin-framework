"""Pixel art: paleta por defecto, lienzos y la hoja de personaje que lee addons/jornada/world/character_frames.gd.

Lo usan los generadores del juego (y el resto de esta librería): `sys.path` con addons/jornada/tools y
`from pixel.core import ...`.
"""
from pathlib import Path

from PIL import Image


def hexc(h: str) -> tuple:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


# ── Paleta ─────────────────────────────────────────────────────────────────
PAL = {
    "ink": "#1F1F1F",            # Negro carbón (oficial)
    "ash0": "#3B3B33", "ash1": "#4F4F44", "ash2": "#666655",  # ash2 = Gris ceniza (oficial)
    "ash3": "#85856F", "ash4": "#A5A48C",
    "grn0": "#243A2C", "grn1": "#355541", "grn2": "#4F7358",  # grn1 = Verde militar (oficial)
    "rus0": "#4E3320", "rus1": "#744D2E", "rus2": "#9A6A42",  # rus1 = Marrón óxido (oficial)
    "yel0": "#D9A073", "yel1": "#FFCD9C", "yel2": "#FFE6C7",  # yel1 = Amarillo tenue (oficial)
    "blu0": "#152840", "blu1": "#1D3557", "blu2": "#2F5282",  # azul nocturno (paleta extendida)
    "wht": "#E4E2D4",
    "lip": "#B05A55",            # labios (extendida)
    "red": "#E63946",            # rojo alerta (paleta extendida)
}
C = {k: hexc(v) for k, v in PAL.items()}
T = (0, 0, 0, 0)


def px_grid(rows: list[str], legend: dict) -> Image.Image:
    h, w = len(rows), len(rows[0])
    img = Image.new("RGBA", (w, h), T)
    for y, row in enumerate(rows):
        assert len(row) == w, f"fila {y} mide {len(row)} y no {w}: {row!r}"
        for x, ch in enumerate(row):
            if ch != ".":
                img.putpixel((x, y), legend[ch])
    return img


# ── Ruido ──────────────────────────────────────────────────────────────────
def noise(x: int, y: int, salt: int = 0) -> int:
    """Ruido determinista (seamless si x,y se toman módulo 16)."""
    n = (x % 16) * 73856093 ^ (y % 16) * 19349663 ^ salt * 83492791
    return (n >> 3) & 0xFF


# ── Lienzo de caracteres (props) ───────────────────────────────────────────
class Canvas:
    """Lienzo de caracteres. Se dibujan formas rellenas y outline() agrega el contorno negro."""

    def __init__(self, w: int = 16, h: int = 32):
        self.w, self.h = w, h
        self.g = [["."] * w for _ in range(h)]

    def rect(self, x: int, y: int, w: int, h: int, ch: str) -> None:
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                if 0 <= xx < self.w and 0 <= yy < self.h:
                    self.g[yy][xx] = ch

    def px(self, x: int, y: int, ch: str) -> None:
        self.rect(x, y, 1, 1, ch)

    def outline(self) -> None:
        src = [row[:] for row in self.g]
        for y in range(self.h):
            for x in range(self.w):
                if src[y][x] != ".":
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.w and 0 <= ny < self.h and src[ny][nx] != ".":
                        self.g[y][x] = "O"
                        break

    def image(self, legend: dict) -> Image.Image:
        return px_grid(["".join(r) for r in self.g], legend)


# ── Hoja de personaje ───────────────────────────────────────────────────────
def save_sheet(frames: dict, path: Path) -> None:
    """Hoja horizontal de 15 cuadros de 16x32: down, up, side (5 cuadros cada una). Si el personaje corre
    (run_down/run_up/run_side), siguen 12 cuadros más: 4 de carrera por vista, en el mismo orden. Si tiene diagonales
    (ddown/dup), siguen 10 de caminata y 8 de carrera (45 en total)."""
    runs = "run_down" in frames
    diag = "ddown" in frames
    sheet = Image.new("RGBA", (16 * (45 if diag else 27 if runs else 15), 32), T)
    for d, direction in enumerate(("down", "up", "side")):
        for i, img in enumerate(frames[direction]):
            sheet.paste(img, ((d * 5 + i) * 16, 0))
        if runs:
            for i, img in enumerate(frames["run_" + direction]):
                sheet.paste(img, ((15 + d * 4 + i) * 16, 0))
    if diag:   # diagonales (protagonista): 5 de caminata por vista y después 4 de carrera por vista
        for d, direction in enumerate(("ddown", "dup")):
            for i, img in enumerate(frames[direction]):
                sheet.paste(img, ((27 + d * 5 + i) * 16, 0))
            for i, img in enumerate(frames["run_" + direction]):
                sheet.paste(img, ((37 + d * 4 + i) * 16, 0))
    sheet.save(path)
