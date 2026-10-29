"""Personajes por descripción: hojas de 15 cuadros de 16x32 (down/up/side x idle + 4 de caminata; más carrera y
diagonales si `runs`). Los retratos de 96x96 salen de la misma descripción en portrait.py.

Cada personaje es un diccionario: cuerpo, prenda, sombrero, pelo, rasgos y accesorios. La figura se arma por capas
con rampas de 4 tonos por material (sombras más frías, luces más cálidas; luz desde arriba-izquierda) y contorno del
color oscuro del material vecino, no negro. La hoja conserva el formato que lee addons/jornada/world/character_frames.gd
(pixel.core.save_sheet).

body: male | female | dog; build: normal | stout | thin; garment: jacket | coat | greatcoat | cassock | apron |
vest | dress | skirt_coat | labcoat; hat: none | rail_cap | flat_cap | fedora | kepi | scarf | cloche | beret
hair: short | bald | bun | braids | long | slick; extras: mustache, beard, stubble, glasses, scar, tie,
briefcase, bag, satchel, collar_up, badge, belt, soot, nose_red, rosary, suitcase, shawl, missing_finger.
kid: filas que se le quitan (chicos); runs: camina suelto, corre y tiene diagonales (el protagonista).
"""

from PIL import Image

from .core import hexc

T = (0, 0, 0, 0)
EYE = hexc("#221C1A")


def ramp(hex_base: str) -> list:
    """4 tonos: [contorno, sombra, base, luz] con corrimiento de matiz."""
    r, g, b, a = hexc(hex_base)

    def mix(c, to, f):
        return tuple(int(c[i] + (to[i] - c[i]) * f) for i in range(3)) + (255,)

    base = (r, g, b, 255)
    shadow = mix((int(r * 0.68), int(g * 0.68), int(b * 0.72)), (40, 42, 78), 0.18)
    dark = mix((int(r * 0.4), int(g * 0.4), int(b * 0.46)), (22, 20, 40), 0.3)
    light = mix(base, (255, 238, 205), 0.28)
    return [dark, shadow, base, light]


SKINS = {"fair": "#EBB993", "pale": "#EDCBB0", "ruddy": "#DDA07C", "weathered": "#C89170", "old": "#E0B699",
         "olive": "#D6A27C"}
SHOE = "#3A2A20"

class Look:
    """Rampas y opciones resueltas de la descripción de un personaje."""

    def __init__(self, d: dict):
        self.d = d
        self.ex = set(d.get("extras", []))
        self.mats = {
            "skin": ramp(SKINS[d["skin"]]), "coat": ramp(d["coat"]), "pants": ramp(d["pants"]),
            "shirt": ramp(d["shirt"]), "hair": ramp(d.get("hair_color", "#4A3426")),
            "hat": ramp(d.get("hat_color", "#2A2A2A")), "shoe": ramp(SHOE),
            "belt": ramp(d.get("belt", "#3A2A20")), "tie": ramp(d.get("tie", "#7A2E34")),
            "scarf": ramp(d.get("scarf", "#7A2E2A")), "apron": ramp(d.get("apron", "#D8D2C0")),
            "shawl": ramp(d.get("shawl", "#5E4A3A")), "gold": ramp("#C9A04A"), "glass": ramp("#9FB3C2"),
            "leather": ramp("#5E3A22"), "metal": ramp("#8A8E94"), "white": ramp("#E9E6DA"),
            "waistcoat": ramp(d.get("waistcoat", "#55524C")), "canvas": ramp(d.get("canvas", "#A39A78")),
        }
        self.mats["eye"] = [EYE, EYE, EYE, EYE]
        c = self.mats["coat"]                                  # canaleta de la pana: entre sombra y base
        self.mats["rib"] = [c[0], c[1], tuple((c[1][i] + 2 * c[2][i]) // 3 for i in range(3)) + (255,), c[3]]
        self.build = {"stout": 1, "thin": -1}.get(d.get("build", "normal"), 0)
        self.female = d["body"] == "female"


class Fig:
    """Grilla de (material, tono) que se pinta en orden y se contornea al final."""

    def __init__(self, look: Look, w: int = 16, h: int = 32):
        self.look, self.w, self.h = look, w, h
        self.g = [[None] * w for _ in range(h)]

    def px(self, x: int, y: int, mat: str, tone: int = 2) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            self.g[y][x] = (mat, tone)

    def rect(self, x: int, y: int, w: int, h: int, mat: str, tone: int = 2) -> None:
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.px(xx, yy, mat, tone)

    def shade_cols(self, x0: int, x1: int, y0: int, y1: int, mat: str) -> None:
        """Volumen: columna izquierda clara, derecha en sombra (solo sobre ese material)."""
        for y in range(y0, y1):
            for x, t in ((x0, 3), (x1, 1)):
                if 0 <= x < self.w and self.g[y][x] and self.g[y][x][0] == mat:
                    self.g[y][x] = (mat, t)

    def image(self) -> Image.Image:
        img = Image.new("RGBA", (self.w, self.h), T)
        for y in range(self.h):
            for x in range(self.w):
                if self.g[y][x]:
                    mat, t = self.g[y][x]
                    img.putpixel((x, y), self.look.mats[mat][t])
        out = img.copy()
        for y in range(self.h):                                # contorno del color oscuro vecino
            for x in range(self.w):
                if self.g[y][x]:
                    continue
                for dx, dy in ((0, 1), (1, 0), (-1, 0), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.w and 0 <= ny < self.h and self.g[ny][nx]:
                        mat = self.g[ny][nx][0]
                        c = self.look.mats[mat][0]
                        out.putpixel((x, y), (int(c[0] * 0.7), int(c[1] * 0.7), int(c[2] * 0.75), 255))
                        break
        return out


# ── Partes de la figura ────────────────────────────────────────────────────
def _hem(look: Look) -> int:
    g = look.d["garment"]
    if g == "cassock":
        return 29
    if g in ("coat", "greatcoat", "labcoat", "skirt_coat", "dress"):
        return 26
    return 22


def _legs(f: Fig, view: str, lift_l: int, lift_r: int, spread: tuple, hem: int) -> None:
    lk = f.look
    if view == "side":
        back_x, front_x = spread
        for x0, lift, near in ((back_x, lift_l, False), (front_x, lift_r, True)):
            top = max(hem, 23)
            if lk.female:
                f.rect(x0, top, 2, 29 - top - lift, "pants", 1 if not near else 2)
            else:
                f.rect(x0, top, 3, 29 - top - lift, "pants", 1 if not near else 2)
            f.rect(x0, 29 - lift, 4, 2, "shoe", 2 if near else 1)
            f.px(x0 + 3, 30 - lift, "shoe", 1)
        return
    for x0, lift, side in ((5, lift_l, 0), (8, lift_r, 1)):
        top = max(hem, 23)
        w = 2 if lk.female else 3
        xx = x0 + (1 if lk.female and side == 0 else 0)
        f.rect(xx, top, w, 29 - top - lift, "pants", 2 if side == 0 else 1)
        if side == 0:
            f.rect(xx, top, 1, 29 - top - lift, "pants", 3)
        if lift >= 2:                                          # la rodilla adelante: más clara, y la canilla en sombra
            f.rect(xx, 25 - lift, w, 1, "pants", 3)
            f.rect(xx, 26 - lift, w, 29 - (26 - lift) - lift, "pants", 1)
        f.rect(x0 - (1 if side == 0 else 0), 29 - lift, 4, 2, "shoe", 2)
        f.rect(x0 - (1 if side == 0 else 0), 30 - lift, 4, 1, "shoe", 1)


def _line(f: Fig, a: tuple, b: tuple, mat: str, tone: int, w: int) -> None:
    """Segmento de `w` px de ancho de `a` a `b` (muslo, canilla, brazo, antebrazo)."""
    steps = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1)
    for s in range(steps + 1):
        f.rect(round(a[0] + (b[0] - a[0]) * s / steps), round(a[1] + (b[1] - a[1]) * s / steps), w, 1, mat, tone)


# Brazos de carrera, relativos al hombro: (codo, mano). Doblados en el codo, bracean adelante y atrás.
ARM_BACK = ((-3, 4), (-6, 2))
ARM_FRONT = ((3, 4), (6, 0))
ARM_MID = ((0, 4), (1, 6))


def _run_arm(f: Fig, shoulder: tuple, pose: tuple, tone: int) -> None:
    mat = "shirt" if "sleeves" in f.look.ex else "coat"
    (ex, ey), (hx, hy) = pose
    elbow = (shoulder[0] + ex, shoulder[1] + ey)
    hand = (shoulder[0] + hx, shoulder[1] + hy)
    _line(f, shoulder, elbow, mat, tone, 2)
    _line(f, elbow, hand, mat, tone, 2)
    f.rect(hand[0], hand[1], 2, 2, "skin", 2 if tone >= 2 else 1)


def _run_legs(f: Fig, stride: tuple, hem: int) -> None:
    """Piernas de perfil en carrera: cada una es cadera → rodilla → pie (x, y), con el muslo y la canilla en
    diagonal. stride = (pierna lejana, pierna cercana), cada una ((rodilla x, y), (pie x, y))."""
    w = 2 if f.look.female else 3
    top = max(hem, 23)
    for (knee, foot), near, hip_x in zip(stride, (False, True), (5, 7)):
        tone = 2 if near else 1
        _line(f, (hip_x, top), knee, "pants", tone, w)
        _line(f, knee, foot, "pants", tone, w)
        fx, fy = foot
        f.rect(fx, fy, 4, 2, "shoe", tone)
        f.px(fx + 3, fy + 1, "shoe", 1)


def _ribs(f: Fig, y0: int, y1: int) -> None:
    """Pana: canaletas verticales en columnas alternas (solo sobre el tono base del saco)."""
    for y in range(y0, y1 + 1):
        for x in range(1, 15, 2):
            if f.g[y][x] == ("coat", 2):
                f.g[y][x] = ("rib", 2)


def _torso_front(f: Fig, u: int, back: bool) -> None:
    lk = f.look
    b = lk.build
    g = lk.d["garment"]
    hem = _hem(lk)
    top = 13 + u
    sx0, sx1 = 3 - b, 12 + b                                  # hombros
    if lk.female:
        sx0, sx1 = 4, 11
    f.rect(sx0, top + 1, sx1 - sx0 + 1, 1, "coat", 2)
    body_x0, body_x1 = 4 - b, 11 + b
    if lk.female:
        body_x0, body_x1 = 5, 10
    for y in range(top + 2, hem + 1):
        x0, x1 = body_x0, body_x1
        if g in ("dress", "skirt_coat", "labcoat", "coat", "greatcoat", "cassock") and y > 19:
            flare = min(2, (y - 19) // 3) if lk.female or g in ("greatcoat", "cassock") else min(1, (y - 20) // 3)
            x0, x1 = x0 - flare, x1 + flare
        f.rect(x0, y, x1 - x0 + 1, 1, "coat", 2)
    f.shade_cols(body_x0 - 2, body_x1 + 2, top + 1, hem + 1, "coat")
    for y in range(top + 1, hem + 1):                          # sombra lateral
        for x in range(16):
            cell = f.g[y][x]
            if cell and cell[0] == "coat":
                right = all(not f.g[y][xx] or f.g[y][xx][0] != "coat" for xx in range(x + 1, min(16, x + 2)))
                left = x == 0 or not f.g[y][x - 1] or f.g[y][x - 1][0] != "coat"
                if right:
                    f.g[y][x] = ("coat", 1)
                elif left:
                    f.g[y][x] = ("coat", 3)
    f.rect(body_x0, hem, body_x1 - body_x0 + 1 + (2 if hem > 22 else 0) - (1 if hem > 22 else 0), 1, "coat", 1)
    if back:
        if hem > 22:
            f.rect(7, 20 + u, 2, hem - 20 - u, "coat", 1)       # abertura trasera
        f.rect(sx0 + 1, top + 1, sx1 - sx0 - 1, 1, "coat", 3)
        if "corduroy" in lk.ex:
            _ribs(f, top + 2, hem)
        return
    # frente: camisa / cuello / botones
    if g not in ("cassock",):
        f.rect(7, top + 1, 2, 2, "shirt", 2)
        f.px(7, top + 3, "shirt", 1)
        f.px(8, top + 3, "shirt", 1)
    if "tie" in lk.ex:
        f.rect(7, top + 2, 2, 5, "tie", 2)
        f.px(8, top + 2, "tie", 1)
    if g == "cassock":
        f.rect(7, top + 1, 2, 1, "white", 3)
        for y in range(top + 3, hem, 2):
            f.px(8, y, "coat", 1)
    elif g == "greatcoat":
        for y in (top + 3, top + 5, top + 8):
            f.px(6, y, "metal", 2)
            f.px(9, y, "metal", 1)
    elif g == "vest":
        f.rect(7, top + 2, 2, hem - top - 2, "shirt", 2)
        for y in (top + 3, top + 5, top + 7):
            f.px(8, y, "gold", 1)
    elif g not in ("dress",):
        f.rect(8, top + 3, 1, hem - top - 3, "coat", 1)
        for y in (top + 4, top + 6, top + 8):
            f.px(7, y, "gold" if "badge" in lk.ex or g == "labcoat" else "coat", 3 if g != "labcoat" else 1)
    if "corduroy" in lk.ex:
        _ribs(f, top + 1, hem)
    if "waistcoat" in lk.ex:                                   # saco abierto: chaleco hasta la cintura
        f.rect(6, top + 2, 4, 21 + u - top - 2, "waistcoat", 2)
        f.rect(9, top + 2, 1, 21 + u - top - 2, "waistcoat", 1)
        f.rect(7, top + 1, 2, 2, "shirt", 2)                   # cuello de la camisa, sin corbata
        f.px(8, top + 2, "shirt", 1)
        f.px(6, top + 1, "coat", 3)                            # solapas
        f.px(9, top + 1, "coat", 1)
        for y in (top + 4, top + 6):
            f.px(8, y, "waistcoat", 0)
        f.rect(7, 21 + u, 2, hem - 20 - u, "pants", 1)         # abertura del saco bajo el chaleco
    if "watch_chain" in lk.ex:
        f.px(6, top + 5, "gold", 3)
        f.px(7, top + 6, "gold", 2)
        f.px(8, top + 6, "gold", 1)
    if "badge" in lk.ex:
        f.px(5, top + 3, "gold", 3)
    if "belt" in lk.ex and g not in ("cassock",):
        f.rect(body_x0, 20 + u, body_x1 - body_x0 + 1, 1, "belt", 2)
        f.px(8, 20 + u, "gold", 2)
    if "apron" in lk.ex:
        for y in range(top + 3, min(hem + 4, 27)):
            f.rect(5, y, 6, 1, "apron", 2 if y > top + 3 else 3)
        f.shade_cols(5, 10, top + 3, 27, "apron")
        f.rect(4, 19 + u, 8, 1, "apron", 1)
    if "scarf" in lk.ex:
        f.rect(5, top, 6, 2, "scarf", 2)
        f.px(5, top, "scarf", 3)
        f.rect(9, top + 2, 2, 3, "scarf", 1)
    if "shawl" in lk.ex:
        f.rect(4, top + 1, 8, 4, "shawl", 2)
        f.px(4, top + 1, "shawl", 3)
        f.rect(6, top + 5, 4, 1, "shawl", 1)
    if "collar_up" in lk.ex:
        f.rect(5, top, 2, 2, "coat", 3)
        f.rect(9, top, 2, 2, "coat", 1)
    if "rosary" in lk.ex:
        for y in range(top + 3, top + 8):
            f.px(6, y, "gold", 1)
        f.px(6, top + 8, "gold", 3)


def _arms_front(f: Fig, u: int, swing: int) -> None:
    lk = f.look
    b = lk.build if not lk.female else 0
    top = 15 + u
    for x0, d, tone in ((2 - b, swing, 2), (12 + b, -swing, 1)):
        mat = "shirt" if "sleeves" in lk.ex else "coat"
        f.rect(x0, top, 2, 6 + d, mat, tone)
        if x0 < 8:
            f.rect(x0, top, 1, 6 + d, mat, 3)
        # Mano derecha (x alta): si falta el dedo, un píxel menos de yema.
        if "missing_finger" in lk.ex and x0 >= 8:
            f.px(x0, top + 6 + d, "skin", 2 if tone >= 2 else 1)
        else:
            f.rect(x0, top + 6 + d, 2, 1, "skin", 2 if x0 < 8 else 1)


def _arms_pump(f: Fig, u: int, pump: int) -> None:
    """Carrera de frente: el brazo que va adelante se dobla y la mano sube hacia el pecho; el que va atrás queda
    corto (se aleja) con la mano a la altura de la cadera. pump=1: adelante el izquierdo de la pantalla."""
    lk = f.look
    b = lk.build if not lk.female else 0
    top = 15 + u
    for x0, inward, forward in ((2 - b, 1, pump > 0), (12 + b, -1, pump < 0)):
        tone = 2 if x0 < 8 else 1
        if forward:
            _run_arm(f, (x0, top), ((inward, 3), (inward * 3, 1)), tone)
        else:
            _run_arm(f, (x0, top), ((-inward, 3), (-inward * 2, 5)), tone)


def _hold(f: Fig, u: int, swing: int) -> None:
    """Objetos en la mano derecha (lado de la sombra)."""
    lk = f.look
    x = 12 + (lk.build if not lk.female else 0)
    y = 22 + u - swing
    if "briefcase" in lk.ex or "suitcase" in lk.ex:
        mat = "leather"
        f.rect(x - 1, y + 1, 5 if "suitcase" in lk.ex else 4, 4, mat, 2)
        f.rect(x - 1, y + 1, 5 if "suitcase" in lk.ex else 4, 1, mat, 3)
        f.px(x + 1, y, mat, 1)
    elif "bag" in lk.ex:
        f.rect(x - 1, y + 1, 4, 3, "leather", 1)
        f.px(x, y + 1, "metal", 3)
    if "satchel" in lk.ex:                                    # bolso de lona cruzado, cuelga en la cadera izquierda
        for i in range(7):
            f.px(4 + i, 14 + u + i, "canvas", 1)
        f.rect(10, 20 + u, 4, 4, "canvas", 2)
        f.rect(10, 20 + u, 4, 1, "canvas", 3)                  # solapa
        f.px(13, 21 + u, "canvas", 1)
        f.px(11, 21 + u, "leather", 2)                         # hebilla


def _satchel_back(f: Fig, u: int) -> None:
    """De espaldas la correa baja del hombro derecho a la cadera izquierda (a la izquierda de la pantalla)."""
    for i in range(7):
        f.px(11 - i, 14 + u + i, "canvas", 1)
    f.rect(2, 20 + u, 4, 4, "canvas", 1)
    f.rect(2, 20 + u, 4, 1, "canvas", 2)


def _head_front(f: Fig, u: int, back: bool) -> None:
    lk = f.look
    d = lk.d
    hat = d.get("hat", "none")
    hair = d.get("hair", "short")
    y0 = 5 + u
    # cara 6x6 (redondeada)
    f.rect(5, y0 + 2, 6, 6, "skin", 2)
    for x, y in ((5, y0 + 7), (10, y0 + 7)):
        f.g[y][x] = None
    f.rect(10, y0 + 2, 1, 5, "skin", 1)
    f.rect(6, y0 + 7, 4, 1, "skin", 1)
    f.px(4, y0 + 4, "skin", 1)
    f.px(11, y0 + 4, "skin", 1)
    f.rect(6, y0 + 8, 4, 1, "skin", 1)                         # cuello
    if back:
        f.rect(4, y0, 8, 7, "hair", 2)
        f.rect(4, y0, 2, 6, "hair", 3)
        f.rect(10, y0 + 1, 2, 6, "hair", 1)
        if hair == "bald":
            f.rect(5, y0, 6, 3, "skin", 2)
            f.rect(5, y0, 2, 2, "skin", 3)
        if hair == "cropped":                                  # nuca rapada bajo la gorra
            for x in (4, 11):
                f.g[y0 + 5][x] = f.g[y0 + 6][x] = None
            f.rect(5, y0 + 5, 6, 1, "hair", 1)
            for x in (5, 10):
                f.g[y0 + 6][x] = None
            f.rect(6, y0 + 6, 4, 2, "skin", 1)
            f.px(4, y0 + 3, "skin", 1)
            f.px(11, y0 + 3, "skin", 1)
        if hair == "bun":
            f.rect(6, y0 + 4, 4, 3, "hair", 1)
            f.rect(7, y0 + 4, 2, 1, "hair", 3)
        if hair == "braids":
            for x in (5, 9):
                f.rect(x, y0 + 7, 2, 6, "hair", 2)
                f.px(x, y0 + 13, "scarf", 2)
        if hair == "long":
            f.rect(4, y0 + 6, 8, 4, "hair", 2)
            f.rect(10, y0 + 6, 2, 4, "hair", 1)
    else:
        # pelo
        if hair == "bald":
            f.rect(4, y0 + 2, 1, 3, "hair", 2)
            f.rect(11, y0 + 2, 1, 3, "hair", 1)
            f.rect(5, y0, 6, 2, "skin", 2)
            f.rect(6, y0, 2, 1, "skin", 3)
        elif hair == "slick":
            f.rect(5, y0, 6, 2, "hair", 2)
            f.rect(5, y0, 4, 1, "hair", 3)
            f.px(4, y0 + 1, "hair", 2)
            f.px(11, y0 + 1, "hair", 1)
            f.rect(4, y0 + 2, 1, 2, "hair", 2)
            f.rect(11, y0 + 2, 1, 2, "hair", 1)
        else:
            f.rect(5, y0, 6, 2, "hair", 2)
            f.rect(5, y0, 3, 1, "hair", 3)
            f.rect(4, y0 + 1, 1, 3 if hair in ("short", "cropped", "bun") else 6, "hair", 2)
            f.rect(11, y0 + 1, 1, 3 if hair in ("short", "cropped", "bun") else 6, "hair", 1)
            if hair in ("bun", "long", "braids"):
                f.px(5, y0 + 2, "hair", 2)
                f.px(10, y0 + 2, "hair", 1)
            if hair == "braids":
                for x in (3, 11):
                    f.rect(x, y0 + 6, 2, 5, "hair", 2 if x < 8 else 1)
                    f.px(x, y0 + 11, "scarf", 2)
            if hair == "long":
                f.rect(4, y0 + 4, 1, 4, "hair", 2)
                f.rect(11, y0 + 4, 1, 4, "hair", 1)
        # rasgos
        f.px(6, y0 + 4, "eye", 0)
        f.px(9, y0 + 4, "eye", 0)
        brow = "white" if "brows_white" in lk.ex else "hair"
        if not lk.female:
            f.px(6, y0 + 3, brow, 1)
            f.px(9, y0 + 3, brow, 1)
        f.px(8, y0 + 5, "skin", 1)                             # nariz
        if "nose_red" in lk.ex:
            f.px(8, y0 + 5, "scarf", 3)
        f.rect(7, y0 + 6, 2, 1, "skin", 1)                     # boca
        if lk.female:
            f.rect(7, y0 + 6, 2, 1, "tie" if "tie" in lk.ex else "skin", 1)
            f.px(6, y0 + 5, "skin", 3)
        if "mustache" in lk.ex:
            f.rect(6, y0 + 6, 4, 1, "hair", 1)
        if "beard" in lk.ex:
            f.rect(5, y0 + 6, 6, 2, "hair", 1)
            f.rect(6, y0 + 8, 4, 1, "hair", 1)
            f.px(7, y0 + 6, "skin", 1)
            f.px(8, y0 + 6, "skin", 1)
        if "stubble" in lk.ex:
            for x in (5, 7, 9, 10):
                f.px(x, y0 + 7 if x not in (5, 10) else y0 + 6, "hair", 1)
        if "glasses" in lk.ex:
            f.px(6, y0 + 4, "glass", 3)
            f.px(9, y0 + 4, "glass", 3)
            f.px(5, y0 + 4, "eye", 0)
            f.px(7, y0 + 4, "eye", 0)
            f.px(8, y0 + 4, "eye", 0)
            f.px(10, y0 + 4, "eye", 0)
        if "scar" in lk.ex:
            f.px(10, y0 + 3, "skin", 3)
            f.px(10, y0 + 5, "skin", 3)
        if "soot" in lk.ex:
            f.px(5, y0 + 5, "hair", 0)
            f.px(10, y0 + 6, "hair", 0)
        if "pale" in lk.ex:
            f.px(6, y0 + 5, "skin", 1)
            f.px(9, y0 + 5, "skin", 1)
    _hat(f, u, hat, back)


def _hat(f: Fig, u: int, hat: str, back: bool, side: bool = False) -> None:
    y0 = 5 + u
    if hat == "none":
        return
    if hat in ("rail_cap", "kepi"):
        crown = 3 if hat == "rail_cap" else 4
        top = y0 - crown + 1
        f.rect(4, top, 8, crown, "hat", 2)
        f.rect(4, top, 8, 1, "hat", 3)
        f.rect(4, y0 + 1, 8, 1, "hat", 1)                      # banda
        if not back:
            f.px(7, y0, "gold", 3)
            f.px(8, y0, "gold", 2)
            if not side:
                f.rect(4, y0 + 2, 8, 1, "hat", 0)              # visera
                f.rect(5, y0 + 3, 6, 1, "skin", 1)             # sombra de la visera
    elif hat == "flat_cap":
        f.rect(5, y0 - 1, 6, 1, "hat", 3)
        f.rect(4, y0, 8, 2, "hat", 2)
        f.rect(4, y0 + 1, 8, 1, "hat", 1)
        if not back and not side:
            f.rect(5, y0 + 2, 7, 1, "hat", 0)
            f.rect(5, y0 + 3, 6, 1, "skin", 1)
    elif hat == "fedora":
        f.rect(5, y0 - 3, 6, 3, "hat", 2)
        f.rect(6, y0 - 3, 4, 1, "hat", 3)
        f.px(7, y0 - 3, "hat", 1)
        f.rect(5, y0, 6, 1, "belt", 1)
        f.rect(2, y0 + 1, 12, 1, "hat", 1)
        if not back and not side:
            f.rect(5, y0 + 2, 6, 1, "skin", 1)
    elif hat == "scarf":
        f.rect(4, y0 - 1, 8, 3, "hat", 2)
        f.rect(4, y0 - 1, 3, 1, "hat", 3)
        f.rect(4, y0 + 2, 1, 5, "hat", 2)
        f.rect(11, y0 + 2, 1, 5, "hat", 1)
        if not back:
            f.rect(6, y0 + 8, 4, 1, "hat", 1)
        else:
            f.rect(4, y0 + 2, 8, 5, "hat", 2)
            f.rect(7, y0 + 7, 2, 2, "hat", 1)
    elif hat == "cloche":
        f.rect(4, y0 - 2, 8, 3, "hat", 2)
        f.rect(5, y0 - 2, 3, 1, "hat", 3)
        f.rect(3, y0 + 1, 10, 1, "hat", 1)
    elif hat == "beret":
        f.rect(4, y0 - 1, 8, 2, "hat", 2)
        f.rect(4, y0 - 1, 3, 1, "hat", 3)
        f.px(8, y0 - 2, "hat", 1)


# ── Vistas ─────────────────────────────────────────────────────────────────
def front(look: Look, lift_l: int = 0, lift_r: int = 0, up: bool = False, back: bool = False,
          swing_amp: int = 1, pump: int = 0) -> Image.Image:
    f = Fig(look)
    u = -1 if up else 0
    swing = swing_amp if lift_r else (-swing_amp if lift_l else 0)
    hem = _hem(look)
    _legs(f, "front", lift_l, lift_r, (0, 0), hem)
    if pump:
        _arms_pump(f, u, pump if not back else -pump)
    else:
        _arms_front(f, u, swing if not back else -swing)
    _torso_front(f, u, back)
    _head_front(f, u, back)
    if not back:
        _hold(f, u, swing)
    elif "satchel" in look.ex:
        _satchel_back(f, u)
    return f.image()


def side(look: Look, back_x: int = 5, front_x: int = 7, lift_l: int = 0, lift_r: int = 0, arm_dx: int = 0,
         up: bool = False, stride: tuple = (), arms: tuple = (), turn: str = "") -> Image.Image:
    """Perfil mirando a la derecha (la izquierda se obtiene con flip_h). `stride`: piernas de carrera (_run_legs);
    `arms`: (pose del brazo lejano, pose del cercano), ver ARM_*. `turn`: diagonales de tres cuartos sobre el cuerpo
    de perfil: "down" gira la cara hacia la cámara (dos ojos, el pecho), "up" la aleja (nuca y pelo)."""
    lk = look
    f = Fig(lk)
    u = -1 if up else 0
    hem = _hem(lk)
    g = lk.d["garment"]
    if stride:
        _run_legs(f, stride, hem)
    else:
        _legs(f, "side", lift_l, lift_r, (back_x, front_x), hem)
    top = 13 + u
    if arms:
        _run_arm(f, (6, top + 2), arms[0], 1)                 # brazo lejano: lo tapa el torso salvo la mano
    x0, x1 = 5, 10 + max(0, lk.build)
    if lk.female:
        x0, x1 = 5, 9
    for y in range(top + 1, hem + 1):
        a, b = x0, x1
        if y > 19 and g in ("dress", "skirt_coat", "labcoat", "coat", "greatcoat", "cassock"):
            flare = min(2, (y - 19) // 3) if lk.female or g in ("greatcoat", "cassock") else min(1, (y - 20) // 3)
            a, b = a - flare + (1 if arm_dx > 0 else 0), b + flare
        f.rect(a, y, b - a + 1, 1, "coat", 2)
        f.px(a, y, "coat", 3)
        f.px(b, y, "coat", 1)
    if "apron" in lk.ex:
        f.rect(x1, top + 3, 1, min(hem + 4, 27) - top - 3, "apron", 2)
    if "belt" in lk.ex:
        f.rect(x0, 20 + u, x1 - x0 + 1, 1, "belt", 2)
    if "tie" in lk.ex or g not in ("cassock",):
        f.px(x1, top + 1, "shirt", 2)
    if "collar_up" in lk.ex:
        f.rect(x0, top, 3, 2, "coat", 3)
    if "scarf" in lk.ex:
        f.rect(x0 + 1, top, 5, 2, "scarf", 2)
    if "shawl" in lk.ex:
        f.rect(x0, top + 1, x1 - x0 + 1, 4, "shawl", 2)
    # cabeza
    y0 = 5 + u
    f.rect(7, y0 + 2, 5, 6, "skin", 2)
    f.g[y0 + 7][11] = None
    f.px(12, y0 + 4, "skin", 2)                               # nariz
    f.px(12, y0 + 5, "skin", 1)
    f.rect(7, y0 + 7, 4, 1, "skin", 1)
    f.rect(8, y0 + 8, 2, 1, "skin", 1)
    f.px(10, y0 + 4, "eye", 0)
    f.px(8, y0 + 4, "skin", 1)                                 # oreja
    hair = lk.d.get("hair", "short")
    if hair == "bald":
        f.rect(6, y0 + 2, 2, 3, "hair", 2)
        f.rect(7, y0, 4, 2, "skin", 2)
    else:
        f.rect(6, y0, 6, 2, "hair", 2)
        f.rect(7, y0, 3, 1, "hair", 3)
        f.rect(5, y0 + 1, 3, 5 if hair not in ("short", "cropped") else 4, "hair", 2)
        f.rect(5, y0 + 1, 1, 4, "hair", 3)
        if hair == "bun":
            f.rect(3, y0 + 2, 3, 3, "hair", 1)
            f.px(3, y0 + 2, "hair", 2)
        if hair == "braids":
            f.rect(5, y0 + 6, 2, 6, "hair", 1)
            f.px(5, y0 + 12, "scarf", 2)
        if hair == "long":
            f.rect(5, y0 + 5, 3, 5, "hair", 2)
    if not lk.female and hair != "bald":
        f.px(10, y0 + 3, "hair" if "brows_white" not in lk.ex else "white", 1)
    if "mustache" in lk.ex:
        f.rect(10, y0 + 6, 2, 1, "hair", 1)
    if "beard" in lk.ex:
        f.rect(8, y0 + 6, 4, 2, "hair", 1)
    if "stubble" in lk.ex:
        f.px(10, y0 + 7, "hair", 1)
        f.px(8, y0 + 6, "hair", 1)
    if "glasses" in lk.ex:
        f.px(10, y0 + 4, "glass", 3)
        f.px(11, y0 + 4, "eye", 0)
        f.px(9, y0 + 4, "eye", 0)
    if "scar" in lk.ex:
        f.px(9, y0 + 5, "skin", 3)
    if "soot" in lk.ex:
        f.px(9, y0 + 6, "hair", 0)
    if turn == "down":                                         # tres cuartos hacia la cámara
        f.px(8, y0 + 4, "eye", 0)                              # el otro ojo, donde estaba la oreja
        f.rect(7, y0 + 3, 2, 1, "hair" if not lk.female else "skin", 1)
        f.rect(8, y0 + 5, 3, 1, "skin", 2)
        if "mustache" in lk.ex:
            f.rect(8, y0 + 6, 4, 1, "hair", 1)
    elif turn == "up":                                         # tres cuartos de espaldas
        f.rect(6, y0 + 1, 5, 6, "hair", 2)
        f.rect(6, y0 + 1, 2, 5, "hair", 3)
        f.px(11, y0 + 4, "skin", 1)
        f.px(11, y0 + 5, "skin", 1)
        f.g[y0 + 4][12] = None
        f.g[y0 + 5][12] = None
    hat = lk.d.get("hat", "none")
    if hat in ("rail_cap", "kepi"):
        crown = 3 if hat == "rail_cap" else 4
        f.rect(5, y0 - crown + 1, 7, crown, "hat", 2)
        f.rect(5, y0 - crown + 1, 7, 1, "hat", 3)
        f.rect(5, y0 + 1, 7, 1, "hat", 1)
        f.rect(11, y0 + 2, 3, 1, "hat", 0)
        f.px(10, y0, "gold", 3)
    elif hat == "flat_cap":
        f.rect(6, y0 - 1, 5, 1, "hat", 3)
        f.rect(5, y0, 7, 2, "hat", 2)
        f.rect(11, y0 + 1, 2, 1, "hat", 0)
    elif hat == "fedora":
        f.rect(6, y0 - 3, 5, 3, "hat", 2)
        f.rect(7, y0 - 3, 3, 1, "hat", 3)
        f.rect(6, y0, 5, 1, "belt", 1)
        f.rect(3, y0 + 1, 11, 1, "hat", 1)
    elif hat == "scarf":
        f.rect(5, y0 - 1, 7, 3, "hat", 2)
        f.rect(5, y0 + 2, 3, 5, "hat", 2)
        f.rect(8, y0 + 7, 3, 1, "hat", 1)
    elif hat == "cloche":
        f.rect(5, y0 - 2, 7, 3, "hat", 2)
        f.rect(4, y0 + 1, 9, 1, "hat", 1)
    elif hat == "beret":
        f.rect(5, y0 - 1, 7, 2, "hat", 2)
        f.px(7, y0 - 2, "hat", 1)
    if "satchel" in lk.ex:
        f.rect(x0 - 2, 20 + u, 3, 4, "canvas", 1)
        f.rect(x0 - 2, 20 + u, 3, 1, "canvas", 2)
        for i in range(6):
            f.px(x0 + 1 + i // 2, top + 1 + i, "canvas", 1)
    if "waistcoat" in lk.ex:
        f.rect(x1, top + 2, 1, 21 + u - top - 2, "waistcoat", 2)
        f.px(x1, top + 1, "shirt", 2)
    if "corduroy" in lk.ex:
        _ribs(f, top + 1, hem)
    if turn == "down":                                         # el pecho asoma: camisa y chaleco del lado de adelante
        f.rect(x1 - 2, top + 1, 2, 4, "shirt", 2)
        if "waistcoat" in lk.ex:
            f.rect(x1 - 3, top + 3, 1, 6, "waistcoat", 2)
    # brazo cercano (encima del torso)
    mat = "shirt" if "sleeves" in lk.ex else "coat"
    if arms:
        _run_arm(f, (8, top + 2), arms[1], 2)
        return f.image()
    ax = 7 + arm_dx
    f.rect(ax, top + 2, 2, 6, mat, 2)
    f.rect(ax, top + 2, 1, 6, mat, 3)
    if "missing_finger" in lk.ex:
        f.px(ax, top + 8, "skin", 2)
    else:
        f.rect(ax, top + 8, 2, 1, "skin", 2)
    if "briefcase" in lk.ex or "suitcase" in lk.ex:
        f.rect(ax - 1, top + 9, 4, 4, "leather", 2)
        f.rect(ax - 1, top + 9, 4, 1, "leather", 3)
    elif "bag" in lk.ex:
        f.rect(ax - 1, top + 9, 3, 3, "leather", 1)
    return f.image()


def shrink(img: Image.Image, cut: int) -> Image.Image:
    """Personaje más bajo: quita `cut` filas entre el pecho y las piernas y alinea con los pies."""
    top = img.crop((0, 0, 16, 16))
    bottom = img.crop((0, 16 + cut, 16, 32))
    out = Image.new("RGBA", (16, 32), T)
    out.paste(top, (0, cut))
    out.paste(bottom, (0, 16 + cut))
    return out


def build_frames(d: dict) -> dict:
    """{"down": [idle, w0..w3], "up": [...], "side": [...]}. Ciclo: paso, pasaje (torso sube), paso, pasaje."""
    if d["body"] == "dog":
        return dog_frames(d)
    lk = Look(d)
    frames = {
        "down": [front(lk), front(lk, lift_r=1), front(lk, up=True), front(lk, lift_l=1), front(lk, up=True)],
        "up": [front(lk, back=True), front(lk, lift_r=1, back=True), front(lk, up=True, back=True),
               front(lk, lift_l=1, back=True), front(lk, up=True, back=True)],
        "side": [side(lk, 5, 7), side(lk, 3, 9, lift_l=1, arm_dx=-2), side(lk, 6, 6, lift_l=2, up=True),
                 side(lk, 9, 3, lift_r=1, arm_dx=2), side(lk, 6, 6, lift_r=2, up=True)],
    }
    if d.get("runs"):
        # el protagonista camina más suelto (piernas más arriba y braceo al doble, como en Stardew Valley) y tiene
        # diagonales de tres cuartos: "ddown" (abajo-derecha) y "dup" (arriba-derecha); la izquierda, con flip_h
        frames["down"] = [front(lk), front(lk, lift_r=2, swing_amp=2), front(lk, up=True), front(lk, lift_l=2, swing_amp=2),
                          front(lk, up=True)]
        frames["up"] = [front(lk, back=True), front(lk, lift_r=2, back=True, swing_amp=2), front(lk, up=True, back=True),
                        front(lk, lift_l=2, back=True, swing_amp=2), front(lk, up=True, back=True)]
        frames["side"] = _side_walk(lk, "")
        frames["ddown"] = _side_walk(lk, "down")
        frames["dup"] = _side_walk(lk, "up")
        frames.update(run_frames(lk))
    cut = d.get("kid", 0)
    if cut:
        frames = {d: [shrink(f, cut) for f in fl] for d, fl in frames.items()}
    return frames


def _side_walk(lk: Look, turn: str) -> list:
    """Caminata de perfil (o diagonal) con rodillas: las piernas salen de la cadera (muslo y canilla, _run_legs); en el
    contacto una va estirada adelante y la otra atrás, en el pasaje la de atrás va doblada con el talón arriba."""
    reach, back = ((8, 26), (10, 29)), ((5, 26), (3, 29))
    lifted, under = ((7, 25), (5, 27)), ((7, 26), (7, 29))
    return [side(lk, 5, 7, turn=turn),
            side(lk, arm_dx=-3, stride=(back, reach), turn=turn),
            side(lk, up=True, stride=(lifted, under), turn=turn),
            side(lk, arm_dx=3, stride=(reach, back), turn=turn),
            side(lk, up=True, stride=(under, lifted), turn=turn)]


def lean(img: Image.Image, dx: int = 1, below: int = 15) -> Image.Image:
    """Inclina hacia adelante: corre `dx` px la cabeza y los hombros; la cadera queda sobre las piernas."""
    out = Image.new("RGBA", img.size, T)
    out.paste(img.crop((0, below, img.width, img.height)), (0, below))
    out.paste(img.crop((0, 0, img.width, below)), (dx, 0))
    return out


def _side_run(lk: Look, turn: str) -> list:
    return [lean(side(lk, arms=(ARM_FRONT, ARM_BACK), stride=(((4, 26), (1, 28)), ((9, 26), (10, 29))), turn=turn)),
            lean(side(lk, up=True, arms=(ARM_MID, ARM_MID), stride=(((8, 25), (8, 28)), ((5, 26), (2, 25))), turn=turn)),
            lean(side(lk, arms=(ARM_BACK, ARM_FRONT), stride=(((8, 26), (10, 29)), ((5, 26), (2, 28))), turn=turn)),
            lean(side(lk, up=True, arms=(ARM_MID, ARM_MID), stride=(((4, 26), (1, 25)), ((9, 25), (9, 28))), turn=turn))]


def run_frames(lk: Look) -> dict:
    """Carrera (solo quien tiene runs=True): 4 cuadros por vista, zancada larga, la pierna de atrás
    recogida en el vuelo, brazos que bracean el doble y el torso inclinado; el cuerpo sube en los vuelos."""
    return {
        "run_down": [front(lk, lift_r=3, pump=1), front(lk, lift_l=1, lift_r=1, up=True),
                     front(lk, lift_l=3, pump=-1), front(lk, lift_l=1, lift_r=1, up=True)],
        "run_up": [front(lk, lift_r=3, back=True, pump=1), front(lk, lift_l=1, lift_r=1, up=True, back=True),
                   front(lk, lift_l=3, back=True, pump=-1), front(lk, lift_l=1, lift_r=1, up=True, back=True)],
        # contacto: una pierna estirada adelante y la otra empujando atrás; vuelo: rodilla al frente y talón atrás
        # los brazos van al revés que las piernas: pierna cercana adelante → brazo cercano atrás
        "run_side": _side_run(lk, ""),
        "run_ddown": _side_run(lk, "down"),
        "run_dup": _side_run(lk, "up"),
    }


# ── Perro (body="dog") ─────────────────────────────────────────────────────────
# Mismo formato de hoja que las personas (16x32, pies en la fila 31) pero el animal ocupa las 14 de abajo.
# Se pinta por zonas (lomo, cuerpo, pecho, patas) y después se le pone el contorno, como al resto del reparto.

def _dog_paint(d: dict, parts: list) -> Image.Image:
    """parts: [(material, [(x, y), ...])] en orden; material ∈ back | fur | light | far | eye."""
    fur, back, light = ramp(d["coat"]), ramp(d["hair_color"]), ramp(d["shirt"])
    color = {"back": back[2], "fur": fur[2], "light": light[2], "far": fur[1], "eye": EYE, "shade": fur[1]}
    img = Image.new("RGBA", (16, 32), T)
    px = img.load()
    for mat, cells in parts:
        for x, y in cells:
            px[x, y] = color[mat]
    out = img.copy()
    po = out.load()
    for y in range(32):
        for x in range(16):
            if px[x, y][3] == 0 and any(0 <= x + dx < 16 and 0 <= y + dy < 32 and px[x + dx, y + dy][3]
                                        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                po[x, y] = fur[0]
    return out


def _rect(x0: int, y0: int, x1: int, y1: int) -> list:
    return [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]


def _dog_side(d: dict, legs: tuple, bob: int = 0) -> Image.Image:
    """De perfil mirando a la derecha. legs = (trasera lejos, trasera cerca, delantera lejos, delantera cerca) en x;
    bob = 1 sube el cuerpo un pixel (pasaje del paso). La cola cuelga: es un perro con miedo."""
    y = 22 - bob
    hl, hn, fl, fn = legs
    return _dog_paint(d, [
        ("far", _rect(hl, y + 5, hl, 30) + _rect(fl, y + 5, fl, 30)),
        ("fur", _rect(2, y, 9, y + 4) + _rect(10, y - 2, 13, y + 1) + _rect(9, y - 1, 10, y + 3)),
        ("back", _rect(3, y, 9, y) + _rect(10, y - 2, 12, y - 2) + [(10, y - 3), (11, y - 3), (10, y - 1)]),
        ("light", _rect(13, y, 14, y + 1) + _rect(10, y + 2, 10, y + 4) + _rect(4, y + 4, 8, y + 4)),
        ("shade", [(1, y + 1), (1, y + 2), (1, y + 3), (1, y + 4)]),
        ("fur", _rect(hn, y + 5, hn, 30) + _rect(fn, y + 5, fn, 30)),
        ("eye", [(12, y - 1), (14, y)]),
    ])


def _dog_front(d: dict, lift: int = 0, back: bool = False) -> Image.Image:
    """De frente (o de espaldas): cabeza ancha con las orejas caídas a los costados, pecho claro y dos patas;
    lift = 1 o 2 levanta una pata (paso)."""
    legs = _rect(6, 27, 6, 30 - (1 if lift == 1 else 0)) + _rect(9, 27, 9, 30 - (1 if lift == 2 else 0))
    ears = _rect(4, 19, 4, 22) + _rect(11, 19, 11, 22)
    if back:
        return _dog_paint(d, [
            ("far", [(5, 30), (10, 30)]),
            ("fur", _rect(5, 18, 10, 22) + _rect(5, 23, 10, 27) + legs),
            ("back", _rect(5, 18, 10, 19) + ears + _rect(7, 20, 8, 26)),
            ("shade", _rect(7, 27, 8, 29)),
        ])
    return _dog_paint(d, [
        ("far", _rect(5, 26, 10, 27) + [(5, 28), (10, 28)]),
        ("fur", _rect(5, 18, 10, 22) + _rect(6, 23, 9, 26) + legs),
        ("back", _rect(6, 18, 9, 18) + ears),
        ("light", _rect(7, 21, 8, 22) + _rect(7, 23, 8, 25)),
        ("eye", [(6, 20), (9, 20), (7, 21), (8, 21)]),
    ])


def dog_frames(d: dict) -> dict:
    """Hoja del perro con el mismo orden que build_frames: [quieto, paso, pasaje, paso, pasaje] por vista."""
    reach, together, swap = (2, 5, 10, 7), (3, 4, 8, 9), (5, 2, 7, 10)
    return {
        "down": [_dog_front(d), _dog_front(d, 1), _dog_front(d), _dog_front(d, 2), _dog_front(d)],
        "up": [_dog_front(d, back=True), _dog_front(d, 1, True), _dog_front(d, back=True), _dog_front(d, 2, True),
               _dog_front(d, back=True)],
        "side": [_dog_side(d, together), _dog_side(d, reach), _dog_side(d, together, 1), _dog_side(d, swap),
                 _dog_side(d, together, 1)],
    }
