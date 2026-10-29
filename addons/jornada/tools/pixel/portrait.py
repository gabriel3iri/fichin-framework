"""Retratos de 96x96: busto de frente o de 3/4 a partir de la descripción del personaje (la de figures.py).

Se pinta en una grilla de (material, tono) con rampas de 6 tonos por material: 0 contorno, 1 sombra honda, 2 sombra,
3 base, 4 luz, 5 brillo. La luz viene de arriba a la izquierda: cara, pelo y ropa se sombrean por la normal de una
forma simple (la cabeza es un óvalo que se angosta en la mandíbula) y encima se dibujan los rasgos a mano: ojos con
blanco, iris, pupila, brillo, párpados y pestañas; cejas con grosor y forma; nariz con el puente iluminado, la punta,
las aletas y la sombra; boca con dos labios; pelo en mechones; arrugas, ojeras, barba y bigote con textura. El de 3/4
se dibuja mirando a la derecha y, si mira a la izquierda, se espeja al final (la luz queda del lado de la cara que se
ve). El contorno de afuera es del tono más oscuro del material vecino, no negro.

Campos que usa de la descripción: body, build, garment, coat, shirt, tie, apron, shawl, scarf, waistcoat, canvas,
belt, hat, hat_color, hair, hair_color, skin, extras, bg, age y kid (ver figures.py). Además acepta `face` (todo
opcional; lo que falta se deduce del resto):
  shape: oval | round | square | long | gaunt | heart        jaw: soft | strong | narrow
  brows: thin | thick | bushy | arched | furrowed           eyes: neutral | narrow | wide | tired | hooded
  eye_color: "#rrggbb"                                       nose: straight | long | hooked | broad | button | crooked
  mouth: neutral | thin | full | frown | smile | smirk      cheeks: none | blush | hollow | ruddy
  age_marks: wrinkles_forehead, crow_feet, nasolabial, jowls, eye_bags, grey_temples, bald_spot
  marks: scar_cheek, scar_brow, mole, freckles, pockmarks, broken_nose, stubble
  expression: neutral | stern | kind | worried | sly | tired | nervous | proud | sad
  turn: front | left | right (3/4 hacia ese lado)
  props: cigarette, pipe, pencil_ear, pince_nez, earrings, medal, rosary, scarf, pearl_necklace
  mustache: brush | walrus | handlebar | pencil (forma del bigote, si tiene; si no, sale del cuerpo y la edad)
"""
import math
import random

from PIL import Image

from .core import hexc
from .figures import SKINS

SIZE = 96
_L = (-0.62, -0.5, 0.6)
_n = math.sqrt(sum(c * c for c in _L))
LIGHT = tuple(c / _n for c in _L)
FRAME = (31, 31, 31, 255)


# ── Color ──────────────────────────────────────────────────────────────────
def _mix(a: tuple, b: tuple, f: float) -> tuple:
    return tuple(max(0, min(255, int(round(a[i] + (b[i] - a[i]) * f)))) for i in range(3)) + (255,)


def _scale(c: tuple, f: float) -> tuple:
    return tuple(max(0, min(255, int(c[i] * f))) for i in range(3)) + (255,)


def _lum(c: tuple) -> float:
    return (0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]) / 255


def ramp6(hx) -> list:
    """[contorno, sombra honda, sombra, base, luz, brillo]: sombras más frías, luces más cálidas."""
    c = hexc(hx) if isinstance(hx, str) else hx
    cool, warm = (34, 30, 64), (255, 238, 206)
    return [_mix(_scale(c, 0.34), cool, 0.4), _mix(_scale(c, 0.58), cool, 0.22), _mix(_scale(c, 0.78), cool, 0.1),
            c, _mix(_scale(c, 1.1), warm, 0.2), _mix(_scale(c, 1.22), warm, 0.42)]


def skin_ramp(hx: str) -> list:
    """La piel tira a rojo en la sombra (la sangre bajo la piel) y a crema en la luz."""
    c = hexc(hx)
    return [_mix(_scale(c, 0.36), (58, 18, 30), 0.45), _mix(_scale(c, 0.64), (120, 40, 54), 0.22),
            _mix(_scale(c, 0.85), (160, 70, 70), 0.12), c, _mix(c, (255, 232, 210), 0.22),
            _mix(c, (255, 246, 232), 0.58)]


def _grey(hx: str) -> str:
    c = hexc(hx)
    g = int(0.5 * (0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]) + 0.5 * 190)
    return _hx((g, g, min(255, g + 4), 255))


def _hx(c: tuple) -> str:
    return "#%02X%02X%02X" % c[:3]


def _smooth(a: float, b: float, x: float) -> float:
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def _hash(x: int, y: int, s: int = 0) -> float:
    """Ruido fijo por pixel en [0, 1) (no usar los bits bajos de una multiplicación: se ven en grilla)."""
    h = (x * 374761393 + y * 668265263 + s * 2246822519) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65536.0


# ── Descripción de la cara ─────────────────────────────────────────────────
FACE_DEFAULTS_BY_EXPRESSION = {
    "neutral": {}, "stern": {"brows": "furrowed", "mouth": "thin", "eyes": "narrow"},
    "kind": {"brows": "arched", "mouth": "smile"}, "worried": {"brows": "worried", "mouth": "frown"},
    "sly": {"brows": "sly", "mouth": "smirk", "eyes": "narrow"}, "tired": {"eyes": "tired", "mouth": "neutral"},
    "nervous": {"brows": "worried", "eyes": "wide", "mouth": "bite"}, "proud": {"mouth": "smirk"},
    "sad": {"brows": "worried", "eyes": "tired", "mouth": "frown"},
}


def resolve_face(d: dict, rng: random.Random) -> dict:
    """La cara completa: lo que trae `face` y, para lo que falta, lo que se deduce del cuerpo, la edad y los rasgos."""
    f = dict(d.get("face") or {})
    ex = set(d.get("extras", []))
    age = d.get("age", 30)
    female = d["body"] == "female"
    build = d.get("build", "normal")
    child = age < 15
    expr = f.get("expression") or ("tired" if age >= 66 and rng.random() < 0.5 else "neutral")
    f["expression"] = expr
    by_expr = FACE_DEFAULTS_BY_EXPRESSION.get(expr, {})
    if "shape" not in f:
        if child:
            f["shape"] = "round"
        elif build == "stout":
            f["shape"] = "square" if not female and rng.random() < 0.6 else "round"
        elif build == "thin":
            f["shape"] = "gaunt" if age >= 50 else "long"
        else:
            f["shape"] = rng.choice(["oval", "heart"] if female else ["oval", "oval", "square", "long"])
    if "jaw" not in f:
        f["jaw"] = "soft" if female or child else "strong" if build == "stout" else "narrow" if build == "thin" else \
            rng.choice(["strong", "soft", "strong"])
    if "brows" not in f:
        f["brows"] = by_expr.get("brows") or ("thin" if child else "arched" if female else
                                              "bushy" if age >= 55 else rng.choice(["thick", "thick", "thin"]))
    if "eyes" not in f:
        f["eyes"] = by_expr.get("eyes") or ("wide" if child else "hooded" if age >= 60 else "neutral")
    if "nose" not in f:
        f["nose"] = "button" if child else rng.choice(["straight", "button", "straight"]) if female else \
            ("broad" if build == "stout" else rng.choice(["straight", "long", "hooked", "straight", "broad"]))
    if "mouth" not in f:
        f["mouth"] = by_expr.get("mouth") or ("full" if female and not child else "neutral")
    if "cheeks" not in f:
        if "nose_red" in ex or d["skin"] == "ruddy":
            f["cheeks"] = "ruddy"
        elif child or female:
            f["cheeks"] = "blush"
        elif build == "thin" and age >= 45:
            f["cheeks"] = "hollow"
        else:
            f["cheeks"] = "none"
    if "age_marks" not in f:
        marks = []
        if age >= 38:
            marks.append("nasolabial")
        if age >= 48:
            marks += ["crow_feet", "wrinkles_forehead"]
        if age >= 58:
            marks.append("eye_bags")
            if build == "stout":
                marks.append("jowls")
        if 45 <= age and _lum(hexc(d.get("hair_color", "#4A3426"))) < 0.5 and not female:
            marks.append("grey_temples")
        f["age_marks"] = marks
    f["age_marks"] = list(f["age_marks"])
    if "marks" not in f:
        f["marks"] = (["stubble"] if "stubble" in ex else []) + (["scar_cheek"] if "scar" in ex else [])
    else:
        f["marks"] = list(f["marks"]) + (["stubble"] if "stubble" in ex and "stubble" not in f["marks"] else [])
        if "scar" in ex and not {"scar_cheek", "scar_brow"} & set(f["marks"]):
            f["marks"].append("scar_cheek")
    if "turn" not in f:
        f["turn"] = "right"
    props = list(f.get("props", []))
    for extra in ("rosary", "scarf"):
        if extra in ex and extra not in props:
            props.append(extra)
    f["props"] = props
    if "eye_color" not in f:
        hair = hexc(d.get("hair_color", "#4A3426"))
        if hair[0] > hair[2] + 60 and hair[1] < 110:          # pelirrojo
            f["eye_color"] = rng.choice(["#5E7A44", "#6A6A3A"])
        elif _lum(hair) > 0.55 and d["skin"] in ("fair", "pale") and age < 45:
            f["eye_color"] = rng.choice(["#4E7090", "#5E8094", "#6A7A70"])
        else:
            f["eye_color"] = rng.choice(["#5A3A26", "#4A3020", "#6A4A2A", "#5A5A44", "#4E6478"])
    if "mustache" in ex and "mustache" not in f:
        if age >= 50 and build != "thin":
            f["mustache"] = "walrus"
        elif build == "thin":
            f["mustache"] = rng.choice(["pencil", "brush"])
        else:
            f["mustache"] = rng.choice(["brush", "brush", "handlebar"])
    return f


# shape: (medio ancho en los pómulos, en la mandíbula, en el mentón, alto de la cabeza)
SHAPES = {"oval": (17.0, 12.2, 5.0, 50), "round": (18.4, 14.6, 6.8, 47), "square": (17.6, 14.8, 7.8, 49),
          "long": (16.0, 11.6, 5.2, 53), "gaunt": (16.4, 11.4, 4.8, 52), "heart": (17.6, 10.4, 3.8, 49)}

# cejas: (grosor adentro, grosor afuera, alto del arco, dónde está el pico, cuánto baja la punta de adentro)
BROWS = {"thin": (2, 1, 1.6, 0.6, 0.0), "thick": (3, 2, 1.2, 0.55, 0.0), "bushy": (3, 3, 1.0, 0.5, 0.5),
         "arched": (2, 1, 2.8, 0.62, 0.0), "furrowed": (3, 2, 0.6, 0.6, 2.0), "worried": (2, 2, 0.4, 0.4, -2.0),
         "sly": (2, 1, 1.8, 0.6, 0.6)}

# nariz: largo desde la línea de los ojos
NOSE_LEN = {"button": 9, "straight": 11, "long": 13, "hooked": 12, "broad": 10, "crooked": 11}

SKIN_MATS = ("skin", "stubble")
HAIRY = ("hair", "grey", "brow")


class Bust:
    def __init__(self, d: dict, seed: str):
        self.d = d
        self.rng = random.Random(f"portrait:{seed}")
        self.f = resolve_face(d, random.Random(f"face:{seed}"))
        self.ex = set(d.get("extras", []))
        self.age = d.get("age", 30)
        self.female = d["body"] == "female"
        self.child = max(0.0, min(1.0, (16 - self.age) / 12))
        self.old = max(0.0, min(1.0, (self.age - 45) / 25))
        self.build = {"stout": 1, "thin": -1}.get(d.get("build", "normal"), 0)
        self.t = 0 if self.f["turn"] == "front" else 1
        self.mirror = self.f["turn"] == "left"
        self.hat = d.get("hat", "none")
        self.hair = d.get("hair", "short")
        self.seed = sum(ord(c) * (i + 1) for i, c in enumerate(seed))
        hair_hex = d.get("hair_color", "#4A3426")
        skin = SKINS.get(d["skin"], "#E0B090")
        self.R = {
            "skin": skin_ramp(skin), "coat": ramp6(d["coat"]), "shirt": ramp6(d["shirt"]),
            "hair": ramp6(hair_hex), "hat": ramp6(d.get("hat_color", "#2A2A2A")),
            "tie": ramp6(d.get("tie", "#7A2E34")), "scarf": ramp6(d.get("scarf", "#7A2E2A")),
            "apron": ramp6(d.get("apron", "#D8D2C0")), "shawl": ramp6(d.get("shawl", "#5E4A3A")),
            "waistcoat": ramp6(d.get("waistcoat", "#55524C")), "canvas": ramp6(d.get("canvas", "#A39A78")),
            "belt": ramp6(d.get("belt", "#3A2A20")), "gold": ramp6("#C9A04A"), "silver": ramp6("#A8ACB0"),
            "leather": ramp6("#5E3A22"), "white": ramp6("#E4E0D6"), "pearl": ramp6("#E8E2D4"),
            "iris": ramp6(self.f["eye_color"]), "brass": ramp6("#B08A3A"), "glass": ramp6("#9FB3C2"),
            "paper": ramp6("#E8E2CC"), "pipe": ramp6("#6A3E24"), "grey": ramp6(_grey(hair_hex)),
            "ember": ramp6("#E06A2A"), "red": ramp6("#9A2E2A"), "black": ramp6("#26242A"),
        }
        self.R["iris"][5] = _mix(self.R["iris"][4], (255, 255, 255), 0.35)
        self.R["eyew"] = [(52, 36, 40, 255), (132, 118, 118, 255), (178, 166, 162, 255), (212, 204, 196, 255),
                          (234, 228, 220, 255), (252, 250, 246, 255)]
        sk = hexc(skin)
        lipf = 0.3 if not self.female else 0.55
        if self.child > 0.3:
            lipf = 0.42
        lip = _mix(_scale(sk, 0.92), (178, 78, 76), lipf)
        self.R["lip"] = skin_ramp(_hx(lip))
        dark = hexc(hair_hex) if _lum(hexc(hair_hex)) < 0.35 else _mix(hexc(hair_hex), (40, 26, 22), 0.55)
        lash = _mix(dark, (22, 14, 16), 0.55)
        self.R["lash"] = [_scale(lash, 0.7), lash, _mix(lash, sk, 0.3), _mix(lash, sk, 0.5), _mix(lash, sk, 0.6),
                          _mix(lash, sk, 0.7)]
        if "brows_white" in self.ex:
            self.R["brow"] = ramp6("#D2D0C8")
        else:
            b = hexc(hair_hex)
            self.R["brow"] = ramp6(hair_hex if _lum(b) < 0.5 else _hx(_scale(b, 0.78)))
        self.R["stubble"] = [_mix(t, self.R["hair"][1], 0.3) for t in self.R["skin"]]
        self.mat = [[None] * SIZE for _ in range(SIZE)]
        self.tone = [[0] * SIZE for _ in range(SIZE)]
        self.col = {}                                          # colores sueltos (brillos, rubor) sobre el material
        self._variation()
        self._geometry()

    # ── grilla ──
    def put(self, x: float, y: float, mat: str, tone: int) -> None:
        x, y = int(math.floor(x)), int(math.floor(y))
        if 0 <= x < SIZE and 0 <= y < SIZE:
            self.mat[y][x] = mat
            self.tone[y][x] = max(0, min(5, tone))
            self.col.pop((x, y), None)

    def is_(self, x: float, y: float, *mats: str) -> bool:
        x, y = int(math.floor(x)), int(math.floor(y))
        return 0 <= x < SIZE and 0 <= y < SIZE and self.mat[y][x] in mats

    def tone_at(self, x: float, y: float) -> int:
        return self.tone[int(math.floor(y))][int(math.floor(x))]

    def shift(self, x: float, y: float, delta: int, *mats: str) -> None:
        """Oscurece o aclara un pixel que ya es de alguno de esos materiales."""
        x, y = int(math.floor(x)), int(math.floor(y))
        if self.is_(x, y, *mats):
            self.tone[y][x] = max(0, min(5, self.tone[y][x] + delta))

    def tint(self, x: float, y: float, color: tuple, f: float, *mats: str) -> None:
        x, y = int(math.floor(x)), int(math.floor(y))
        if self.is_(x, y, *mats):
            base = self.col.get((x, y)) or self.R[self.mat[y][x]][self.tone[y][x]]
            self.col[(x, y)] = _mix(base, color, f)

    def line(self, pts: list, mat: str, tone: int, only: tuple = ()) -> None:
        """Polilínea de 1 px por los puntos dados (si `only`, solo pinta sobre esos materiales)."""
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            n = int(max(abs(bx - ax), abs(by - ay))) + 1
            for i in range(n + 1):
                q = i / max(1, n)
                x, y = ax + (bx - ax) * q, ay + (by - ay) * q
                if not only or self.is_(x, y, *only):
                    self.put(x, y, mat, tone)

    def lit(self, nx: float, ny: float, nz: float, bias: float = 0.0) -> int:
        n = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
        v = (nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]) / n + bias
        return 1 if v < 0.1 else 2 if v < 0.4 else 3 if v < 0.77 else 4 if v < 0.93 else 5

    # ── variación: lo que hace que dos caras con la misma descripción no sean iguales ──
    def _variation(self) -> None:
        r = self.rng
        f = self.f
        k = self.child
        shape = f["shape"]
        self.eye_gap = 8.4 + {"round": 0.5, "square": 0.3, "long": -0.4, "gaunt": -0.2, "heart": 0.2}.get(shape, 0) \
            + r.uniform(-0.6, 0.6) + 0.4 * k
        self.eye_w = 10 + (1 if k > 0.5 else 0) - (1 if f["eyes"] == "narrow" and r.random() < 0.5 else 0)
        self.eye_h = {"wide": 6, "narrow": 4, "tired": 5, "hooded": 4}.get(f["eyes"], 5) + (1 if k > 0.6 else 0)
        self.eye_dy = r.choice([-1, 0, 0, 1])
        self.tilt = {"sly": 0.8, "stern": 0.4, "sad": -0.6, "tired": -0.2, "worried": -0.4}.get(f["expression"], 0.0)
        self.tilt += r.uniform(-0.4, 0.4) + (0.3 if self.female else 0)
        self.nose_len = NOSE_LEN.get(f["nose"], 11) + r.choice([-1, 0, 0, 1]) - int(round(3 * k))
        self.mouth_gap = 5 + r.choice([0, 0, 1]) + (1 if shape in ("long", "gaunt") else 0) - int(round(1.5 * k))
        mw = {"thin": 4.6, "full": 5.2, "smile": 5.6, "frown": 5.0, "smirk": 5.0, "bite": 4.4}.get(f["mouth"], 5.0)
        self.mouth_w = mw + r.uniform(-0.5, 0.5) - 0.4 * (1 if self.female else 0) - 1.4 * k + 0.4 * self.build
        self.brow_h = 4.5 + (0.8 if f["brows"] == "arched" else 0) + r.uniform(-0.4, 0.6) + 0.6 * k

    # ── geometría de la cabeza ──
    def _geometry(self) -> None:
        W, Wj, Wc, Hh = SHAPES.get(self.f["shape"], SHAPES["oval"])
        jaw = self.f["jaw"]
        Wj += {"strong": 1.2, "narrow": -1.0}.get(jaw, 0.0)
        Wc += {"strong": 1.6, "narrow": -0.8}.get(jaw, 0.0)
        if self.female:
            W, Wj, Wc, Hh = W - 0.8, Wj - 0.8, Wc - 0.5, Hh - 1
        W += 0.8 * self.build
        Wj += 1.0 * self.build
        W += self.rng.uniform(-0.5, 0.5)
        Hh += self.rng.choice([-1, 0, 0, 1])
        k = self.child
        W += 1.6 * k
        Wj += 1.8 * k
        Wc += 1.2 * k
        Hh = int(round(Hh - 8 * k))
        self.W, self.Wj, self.Wc = W, Wj, Wc
        self.top = 12 + int(round(10 * k))
        self.chin = self.top + Hh
        self.H = Hh
        self.cxh = 48 - 1.5 * self.t
        self.fx = self.cxh + 5.5 * self.t                      # eje de la cara (se corre hacia donde mira)
        self.ey = self.top + int(round(Hh * (0.5 + 0.06 * k))) + self.eye_dy
        self.rows = {}
        for y in range(self.top, self.chin + 1):
            v = (y + 0.5 - self.top) / Hh
            hw = self._half(v)
            off = self.t * 3.6 * _smooth(0.5, 1.0, v)
            if self.t:
                near = 1.17 if v < 0.62 else 1.17 - 0.2 * _smooth(0.62, 0.95, v)
                far = 0.93 - 0.06 * _smooth(0.55, 0.9, v)
                if abs(v - 0.5) < 0.05:                        # la cuenca del ojo lejano
                    far -= 0.025
                if 0.56 < v < 0.68:                            # el pómulo lejano
                    far += 0.03
                l, r = near, far
                hl = self._half(v, near=True)
            else:
                l = r = 1.0
                hl = hw
            self.rows[y] = (self.cxh + off - hl * l, self.cxh + off + hw * r)

    def _half(self, v: float, near: bool = False) -> float:
        W, Wj, Wc = self.W, self.Wj, self.Wc
        if near:                                               # de 3/4 se ve el ángulo de la mandíbula
            Wj = max(Wj, W * 0.84)
            Wc = max(Wc, W * 0.42)
        if v < 0.5:                                            # cráneo: superelipse, arriba más plano
            q = (0.5 - v) / 0.5
            return W * max(0.0, 1 - q ** 2.0) ** (1 / 2.0) + 0.4   # redondo: la cabeza no es una caja
        if v < 0.5:
            return W
        if v < 0.86:
            h = W + (Wj - W) * _smooth(0.5, 0.86, v)
            if self.f["shape"] == "gaunt" or self.f["cheeks"] == "hollow":
                h -= 0.9 * math.sin(math.pi * (v - 0.6) / 0.26)
            if "jowls" in self.f["age_marks"]:
                h += 1.1 * _smooth(0.7, 0.86, v)
            return h
        q = (v - 0.86) / 0.14
        return Wc + (Wj - Wc) * math.sqrt(max(0.0, 1 - q ** 1.7))   # mentón redondeado

    def in_head(self, x: float, y: float) -> bool:
        y = int(math.floor(y))
        if y not in self.rows:
            return False
        l, r = self.rows[y]
        return l <= x + 0.5 <= r

    def X(self, dx: float) -> float:
        return self.fx + dx

    # ── pintura ──
    def render(self) -> Image.Image:
        self.back_hair()
        self.body()
        self.neck()
        self.head()
        self.features()
        self.facial_hair()
        self.front_hair()
        self.ears()
        self.glasses()
        self.hat_layer()
        self.front_long_hair()
        self.props()
        return self.image()

    # cuerpo ---------------------------------------------------------------
    def body(self) -> None:
        d, g = self.d, self.d["garment"]
        self.bx = 48 + 2.0 * self.t                            # eje del pecho
        nb = self.neck_half()
        sw = 35 + 3.5 * self.build - (5 if self.female else 0) - 9 * self.child
        self.sw = sw
        y0 = self.chin + 6 - int(round(2 * self.child))
        self.body_top = y0
        self.span = {}
        slope = 13
        for y in range(y0, SIZE):
            s = _smooth(0, slope, y - y0)
            reach = nb + 1.5 + (sw - nb - 1.5) * math.sqrt(s) + max(0, y - y0 - slope) * 0.3
            l = self.bx - reach * (1.04 if self.t else 1)
            r = self.bx + reach * (0.94 if self.t else 1)
            self.span[y] = (l, r)
            for x in range(int(l), int(math.ceil(r))):
                if not (l <= x + 0.5 <= r):
                    continue
                u = (x + 0.5 - self.bx) / max(reach, 1)
                top = (y - y0) < slope and abs(u) > 0.35            # el hombro, que mira para arriba
                ny = -0.75 if top else 0.15
                tone = self.lit(u * 0.95, ny, 0.72)
                self.put(x, y, "coat", min(tone, 4))
        self.cloth_texture()
        for side in (-1, 1):                                    # pliegue entre el brazo y el pecho
            ax = self.bx + side * (sw - 9)
            for y in range(y0 + 12, SIZE):
                xx = ax + side * (y - y0 - 12) * 0.14
                self.shift(xx, y, -1, "coat")
                if side < 0:
                    self.shift(xx + 1, y, +1, "coat")
        for i in range(3):                                      # arrugas de la tela bajo la axila
            yy = y0 + 18 + i * 4
            for side in (-1, 1):
                x0 = self.bx + side * (sw - 11)
                self.line([(x0, yy), (x0 - side * 4, yy + 2)], "coat", 2, ("coat",))
        if g == "vest":
            self.vest()
        elif g == "cassock":
            self.cassock()
        elif g == "greatcoat":
            self.greatcoat()
        elif g == "dress":
            self.dress()
        elif g == "apron":
            self.vest(apron=True)
        else:                                                  # jacket, coat, skirt_coat, labcoat
            self.lapels(long=g in ("coat", "labcoat"))
        if "apron" in self.ex or g == "apron":
            self.apron_bib()
        if "shawl" in self.ex:
            self.shawl()
        if "badge" in self.ex and g != "greatcoat":
            self.pin(self.bx - 15, y0 + 14)
        if "satchel" in self.ex or "bag" in self.ex:
            mat = "canvas" if "satchel" in self.ex else "leather"
            for y in range(y0 + 1, SIZE):
                x = self.bx - sw + 8 + (y - y0) * 1.05
                for i, t in enumerate((4, 3, 3, 2, 1)):
                    if self.is_(x + i, y, "coat", "shirt", "shawl", "apron", "waistcoat", "tie"):
                        self.put(x + i, y, mat, t)
                if (y - y0) % 3 == 0:
                    self.shift(x + 2, y, -1, mat)

    def cloth_texture(self) -> None:
        """Textura de la tela: sarga en diagonal, pana en canaletas o paño grueso del capote."""
        g = self.d["garment"]
        kind = "rib" if "corduroy" in self.ex else "heavy" if g in ("greatcoat", "cassock") else \
            "knit" if g == "dress" and self.d.get("body") == "female" and False else "twill"
        for y in range(self.body_top, SIZE):
            for x in range(SIZE):
                if not self.is_(x, y, "coat"):
                    continue
                t = self.tone[y][x]
                if kind == "rib":
                    if x % 2 == 0 and t > 1:
                        self.tone[y][x] = t - 1
                    elif t == 4 and _hash(x, y, 3) < 0.3:
                        self.tone[y][x] = 3
                elif kind == "heavy":
                    if _hash(x, y, 5) < 0.12 and t > 1:
                        self.tone[y][x] = t - 1
                else:
                    n = _hash(x, y, 1)
                    if n < 0.1 and t > 1:
                        self.tone[y][x] = t - 1
                    elif n > 0.95 and t < 4:
                        self.tone[y][x] = t + 1

    def pin(self, x: float, y: float) -> None:
        for dx, dy, t in ((0, 0, 4), (1, 0, 3), (2, 0, 3), (0, 1, 3), (1, 1, 5), (2, 1, 2), (0, 2, 2), (1, 2, 2),
                          (2, 2, 1), (1, 3, 1)):
            self.put(x + dx, y + dy, "gold", t)

    def neck_half(self) -> float:
        return 7.6 + 1.4 * self.build - (1.4 if self.female else 0) - 1.0 * self.child

    def collar(self, mat: str = "shirt", spread: float = 6.5, depth: int = 7) -> None:
        """Cuello de camisa: dos puntas a los lados de la garganta, con la costura y la sombra."""
        nb = self.neck_half()
        y0 = self.body_top - 2
        for side in (-1, 1):
            for i in range(depth):
                w = int(round(spread - i * spread / depth)) + 1
                for j in range(w):
                    x = self.bx + side * (nb + 0.5 - i * nb / depth * 0.9 + j - 1)
                    tone = 4 if side < 0 else 3
                    if j == w - 1 or i == depth - 1:
                        tone -= 2
                    elif j == 0:
                        tone += 1
                    self.put(x, y0 + i, mat, tone)
            self.put(self.bx + side * (nb + 1.5), y0, mat, 1)
            self.put(self.bx + side * (nb + 1.5), y0 + 1, mat, 2)

    def v_opening(self, depth: int, inner: str = "shirt") -> tuple:
        """La V del escote: devuelve (y del vértice, función medio ancho)."""
        nb = self.neck_half()
        y0 = self.body_top
        apex = y0 + depth

        def half(y: float) -> float:
            return max(0.0, (nb + 0.8) * (1 - (y - y0) / depth))
        for y in range(y0 - 1, apex + 1):
            h = half(y)
            for x in range(int(self.bx - h - 1), int(self.bx + h + 2)):
                if abs(x + 0.5 - self.bx) <= h:
                    self.put(x, y, inner, 3 if x + 0.5 < self.bx + h * 0.4 else 2)
        return apex, half

    def tie_or_buttons(self, apex: int, inner: str = "shirt") -> None:
        y0 = self.body_top
        if "tie" in self.ex:
            for dx, t in ((-2, 3), (-1, 4), (0, 3), (1, 3), (2, 1)):          # el nudo
                self.put(self.bx + dx, y0, "tie", t)
            for dx, t in ((-1, 3), (0, 3), (1, 2)):
                self.put(self.bx + dx, y0 + 1, "tie", t)
                self.put(self.bx + dx, y0 + 2, "tie", t - 1)
            for y in range(y0 + 3, apex + 4):
                w = 1 if y < y0 + 5 else 2
                for dx in range(-w, w + 1):
                    t = 4 if dx == -w else 3 if dx <= 0 else 2
                    if (y - y0 + dx) % 5 == 0:
                        t -= 1                                   # la raya en diagonal
                    self.put(self.bx + dx, y, "tie", t)
                self.put(self.bx + w + 1, y, "tie", 1)
        else:
            for y in range(y0 + 4, apex, 4):
                self.put(self.bx, y, inner, 5)
                self.put(self.bx, y + 1, inner, 1)

    def lapels(self, long: bool) -> None:
        y0 = self.body_top
        inner = "waistcoat" if "waistcoat" in self.ex else "shirt"
        depth = 18 if not self.female else 14
        apex, half = self.v_opening(depth, "shirt")
        if inner == "waistcoat":                              # chaleco cerrado más abajo, con botones y la cadena
            for y in range(y0 + 7, SIZE):
                h = half(y) if y <= apex else 0
                for x in range(int(self.bx - h - 6), int(self.bx + h + 7)):
                    if abs(x + 0.5 - self.bx) <= max(h, 0) + 5 and (y > apex or abs(x + 0.5 - self.bx) > h * 0.0):
                        if y <= apex and abs(x + 0.5 - self.bx) < h - 1 and y < y0 + 9:
                            continue
                        self.put(x, y, "waistcoat", 3 if x < self.bx else 2)
            for y in range(y0 + 9, SIZE):
                self.put(self.bx + 0.5, y, "waistcoat", 1)
            for y in range(y0 + 10, SIZE, 4):
                self.put(self.bx - 0.5, y, "brass", 4)
                self.put(self.bx - 0.5, y + 1, "waistcoat", 1)
            if "watch_chain" in self.ex:
                for i in range(9):
                    self.put(self.bx - 9 + i, y0 + 21 + abs(i - 4) // 2 - 1, "gold", 5 if i % 2 else 3)
        self.collar()
        self.tie_or_buttons(apex)
        # solapas: una franja a cada lado de la V, con muesca
        for side in (-1, 1):
            for y in range(y0 - 2, min(SIZE, apex + 3)):
                h = half(y)
                w = 5 if y < y0 + 7 else 4
                for i in range(w + 1):
                    x = self.bx + side * (h + 1 + i)
                    tone = 4 if side < 0 else 2
                    if i == 0:
                        tone = 5 if side < 0 else 3
                    if i == w:
                        tone = 1
                    self.put(x, y, "coat", tone)
            ny = y0 + 6                                          # muesca de la solapa
            for k in range(3):
                self.put(self.bx + side * (half(ny) + 6.5 + k * 0.6), ny - k, "coat", 1)
            self.put(self.bx + side * (half(ny) + 7.5), ny + 1, "coat", 0)
        # cierre y botones del saco
        for y in range(apex + 2, SIZE):
            self.put(self.bx + 0.5, y, "coat", 1)
        for y in range(apex + 4, SIZE, 7):
            self.put(self.bx - 2, y, "coat", 5)
            self.put(self.bx - 1, y, "coat", 4)
            self.put(self.bx - 2, y + 1, "coat", 2)
            self.put(self.bx - 1, y + 1, "coat", 1)
        # bolsillo de pecho con el ribete
        px = self.bx - self.sw + 13
        py = apex - 1
        for i in range(8):
            self.put(px + i, py, "coat", 1)
            self.put(px + i, py - 1, "coat", 4)
        if self.d["garment"] == "labcoat":
            for y in range(py - 5, py):
                self.put(px + 2, y, "tie", 3)
                self.put(px + 4, y, "silver", 4)
            self.put(px + 2, py - 6, "silver", 5)

    def vest(self, apron: bool = False) -> None:
        """Chaleco: las mangas de la camisa en los hombros y el chaleco abierto en V con botones."""
        y0 = self.body_top
        sw = self.sw
        for y, (l, r) in self.span.items():
            for x in range(int(l), int(math.ceil(r))):
                if not self.is_(x, y, "coat"):
                    continue
                rel = abs(x + 0.5 - self.bx)
                arm = sw - 11 + max(0, (y - y0 - 15)) * 0.2
                if rel > arm or (y < y0 + 5 and rel > self.neck_half() + 5):
                    t = self.tone[y][x]
                    self.put(x, y, "shirt", max(2, min(t + 1, 4)) if y > y0 + 5 else min(t + 1, 5))
        for side in (-1, 1):                                    # sisa
            for y in range(y0 + 4, SIZE):
                arm = sw - 11 + max(0, (y - y0 - 15)) * 0.2
                self.put(self.bx + side * arm, y, "coat", 1)
                self.put(self.bx + side * (arm + 1), y, "shirt", 2)
        for side in (-1, 1):                                    # pliegues de la manga
            for y in range(y0 + 10, SIZE, 5):
                x0 = self.bx + side * (sw - 4)
                self.line([(x0, y), (x0 - side * 3, y + 2)], "shirt", 2, ("shirt",))
        if apron:
            self.collar()
            return
        apex, half = self.v_opening(19, "shirt")
        self.collar()
        self.tie_or_buttons(apex)
        for side in (-1, 1):
            for y in range(y0 + 3, apex + 1):
                self.put(self.bx + side * (half(y) + 1), y, "coat", 1)
                self.put(self.bx + side * (half(y) + 2), y, "coat", 4 if side < 0 else 3)
        for y in range(apex + 3, SIZE, 4):
            self.put(self.bx - 1, y, "brass", 5)
            self.put(self.bx, y, "brass", 3)
            self.put(self.bx - 1, y + 1, "coat", 1)
        for y in range(apex + 1, SIZE):
            self.put(self.bx + 1, y, "coat", 1)
        for side in (-1, 1):                                    # bolsillitos del chaleco
            px = self.bx + side * 9 - 3
            for i in range(6):
                self.put(px + i, apex + 6, "coat", 1)

    def cassock(self) -> None:
        y0 = self.body_top
        nb = self.neck_half()
        for y in range(y0 - 5, y0 + 1):                       # cuello alto
            for x in range(int(self.bx - nb - 2), int(self.bx + nb + 3)):
                rel = (x + 0.5 - self.bx) / (nb + 1.5)
                if abs(rel) <= 1.05:
                    self.put(x, y, "coat", 4 if rel < -0.5 else 3 if rel < 0.4 else 2)
            self.put(self.bx - nb - 2, y, "coat", 1)
        for dx, t in ((-2, 4), (-1, 5), (0, 5), (1, 4), (2, 3)):    # alzacuello blanco
            self.put(self.bx + dx, y0 - 4, "white", t)
            self.put(self.bx + dx, y0 - 3, "white", t - 1)
        self.put(self.bx - 1, y0 - 2, "white", 3)
        self.put(self.bx, y0 - 2, "white", 2)
        for y in range(y0 + 1, SIZE):                          # la botonadura de la sotana
            self.put(self.bx + 1, y, "coat", 1)
            if (y - y0) % 3 == 0:
                self.put(self.bx, y, "coat", 5)
        for side in (-1, 1):                                    # pliegues
            for y in range(y0 + 14, SIZE):
                self.shift(self.bx + side * 8 + side * (y - y0) * 0.12, y, -1, "coat")
                self.shift(self.bx + side * 9 + side * (y - y0) * 0.12, y, +1, "coat")

    def greatcoat(self) -> None:
        """Capote: cuello volcado alto, doble fila de botones y charreteras."""
        y0 = self.body_top
        nb = self.neck_half()
        apex, half = self.v_opening(9, "shirt")
        self.collar(spread=5, depth=5)
        self.tie_or_buttons(apex)
        metal = "gold" if "badge" in self.ex else "silver"
        for side in (-1, 1):                                    # cuello del capote, alto a los lados del cuello
            for y in range(y0 - 6, y0 + 12):
                h = half(y) if y >= y0 else nb + 0.8
                w = 6 if y < y0 + 6 else 7
                for i in range(w):
                    x = self.bx + side * (h + 1 + i)
                    tone = (4 if side < 0 else 2) if 0 < i < w - 1 else 1
                    if y == y0 - 6:
                        tone = 4 if side < 0 else 3
                    self.put(x, y, "coat", tone)
            if "badge" in self.ex:                               # las mostrine del cuello
                for dy in range(2, 6):
                    for i in range(2, 4):
                        self.put(self.bx + side * (half(y0 + dy) + i + 1), y0 + dy, "red", 3 if side < 0 else 2)
                self.put(self.bx + side * (half(y0 + 3) + 3), y0 + 3, metal, 5)
        for side in (-1, 1):                                    # doble botonadura
            for y in range(y0 + 13, SIZE, 7):
                x = self.bx + side * 7
                self.put(x, y, metal, 5)
                self.put(x + 1, y, metal, 3)
                self.put(x, y + 1, metal, 3)
                self.put(x + 1, y + 1, metal, 1)
        for y in range(apex + 1, SIZE):
            self.put(self.bx + 2, y, "coat", 1)
        for side in (-1, 1):                                    # charreteras
            sx = self.bx + side * (self.sw - 7)
            for i in range(10):
                x = sx - side * i
                yy = y0 + 8 - int(round(i * 0.45))
                self.put(x, yy - 1, "coat", 5 if side < 0 else 3)
                self.put(x, yy, "coat", 4 if side < 0 else 2)
                self.put(x, yy + 1, "coat", 1)
            self.put(sx - side * 8, y0 + 4, metal, 5)
        if "belt" in self.ex:                                   # correaje en diagonal
            for y in range(y0 + 3, SIZE):
                x = self.bx - self.sw + 11 + (y - y0 - 3) * 1.15
                for i, t in ((0, 4), (1, 5), (2, 4), (3, 3), (4, 2), (5, 1)):
                    self.put(x + i, y, "belt", t)

    def dress(self) -> None:
        y0 = self.body_top
        nb = self.neck_half()
        dark = _lum(hexc(self.d["coat"])) < 0.2
        for y in range(y0 - 1, y0 + 6):                        # escote redondo
            h = nb + 2 - (y - y0) * 1.0 if y >= y0 else nb + 2
            for x in range(int(self.bx - h - 1), int(self.bx + h + 2)):
                if abs(x + 0.5 - self.bx) <= h:
                    self.put(x, y, "skin" if not dark else "coat", 3 if x < self.bx else 2)
        for side in (-1, 1):                                   # cuello redondo de la blusa, con puntilla
            for i in range(9):
                x = self.bx + side * (nb + 3 - i * 0.6)
                y = y0 - 1 + i * 0.75
                self.put(x, y, "shirt", 4 if side < 0 else 3)
                self.put(x + side, y, "shirt", 3 if side < 0 else 2)
                self.put(x + side * 2, y + 1, "shirt", 1)
                if i % 2 == 0:
                    self.put(x + side * 2, y + 2, "shirt", 4)
        for y in range(y0 + 9, SIZE, 4):                       # botones del corpiño
            self.put(self.bx - 0.5, y, "coat", 5)
            self.put(self.bx - 0.5, y + 1, "coat", 1)
        for side in (-1, 1):                                   # costuras del corpiño
            for y in range(y0 + 10, SIZE):
                self.shift(self.bx + side * 10 - side * (y - y0 - 10) * 0.1, y, -1, "coat")

    def apron_bib(self) -> None:
        y0 = self.body_top
        top = y0 + 15
        for side in (-1, 1):                                    # tiras al cuello
            for y in range(y0 - 1, top):
                x = self.bx + side * (self.neck_half() + 2 + (y - y0) * 0.35)
                self.put(x, y, "apron", 4 if side < 0 else 2)
                self.put(x + side, y, "apron", 3 if side < 0 else 1)
        for y in range(top, SIZE):
            hw = 10.5 + (y - top) * 0.35
            for x in range(int(self.bx - hw), int(self.bx + hw + 1)):
                rel = (x + 0.5 - self.bx) / hw
                tone = 4 if rel < -0.45 else 3 if rel < 0.5 else 2
                if y == top:
                    tone = 5 if rel < 0 else 4
                elif y == top + 1:
                    tone = 2                                     # el dobladillo de arriba
                if _hash(x, y, 21) < 0.06:
                    tone = max(1, tone - 1)                      # manchas y uso
                self.put(x, y, "apron", tone)
            self.put(self.bx + hw + 1, y, "apron", 1)
        for i, fx in enumerate((-5, 2, 7)):                     # pliegues que caen
            for y in range(top + 4, SIZE):
                self.shift(self.bx + fx + (y - top) * 0.08 * (i - 1), y, -1, "apron")
                self.shift(self.bx + fx - 1 + (y - top) * 0.08 * (i - 1), y, +1, "apron")

    def shawl(self) -> None:
        """Chal de lana tejido: punto en espiga, cae por los hombros y se cruza adelante."""
        y0 = self.body_top
        for y in range(y0 - 2, SIZE):
            for side in (-1, 1):
                outer = self.span[max(y0, y)][0 if side < 0 else 1] + side * 0.6 if y >= y0 else \
                    self.bx + side * (self.neck_half() + 4)
                inner = self.bx + side * max(1.0, self.neck_half() + 3 - (y - y0) * 0.8)
                lo, hi = sorted((outer, inner))
                for x in range(int(lo), int(math.ceil(hi))):
                    if not (lo <= x + 0.5 <= hi):
                        continue
                    if y < y0 and not self.is_(x, y + 1, "coat", "shirt", "skin"):
                        continue
                    u = (x + 0.5 - self.bx) / max(1, self.sw)
                    tone = self.lit(u, 0.1 if y > y0 + 8 else -0.5, 0.7)
                    tone = min(4, tone)
                    if (x + abs(y % 4 - 2)) % 3 == 0:
                        tone -= 1                                   # el punto en espiga
                    elif _hash(x, y, 17) < 0.08:
                        tone -= 1
                    if abs(x + 0.5 - inner) < 1:
                        tone = 1
                    self.put(x, y, "shawl", tone)
        for y in range(y0 + 14, SIZE, 2):                       # flecos
            self.put(self.bx - 2, y, "shawl", 2)

    # cuello y cabeza ------------------------------------------------------
    def neck(self) -> None:
        nb = self.neck_half()
        nx = self.cxh + self.t * 2.4
        for y in range(self.chin - 12, self.body_top + 2):
            for x in range(int(nx - nb - 1), int(nx + nb + 2)):
                rel = (x + 0.5 - nx) / nb
                if abs(rel) > 1:
                    continue
                if self.mat[y][x] is not None and y >= self.body_top - 2:
                    continue
                tone = 3 if rel < 0.2 else 2
                if rel < -0.75:
                    tone = 2
                self.put(x, y, "skin", tone)
        self.neck_x = nx
        if not self.female and self.build <= 0 and self.child < 0.5:   # nuez
            ax = nx + 1.0 * self.t
            self.put(ax, self.chin + 4, "skin", 4)
            self.put(ax, self.chin + 5, "skin", 3)
            self.put(ax + 1, self.chin + 5, "skin", 1)
        for i in range(4):                                      # el tendón del cuello del lado de la luz
            self.put(nx - nb + 2 + i * 0.4, self.chin + 2 + i, "skin", 4)

    def head(self) -> None:
        """La cara en tres planos de luz con bordes curvos (el costado con luz, el frente, el lado lejano en sombra),
        más los brillos de la frente, el pómulo y el mentón. Nada de bandas verticales."""
        t = self.t
        H = self.H

        def lerp(pts: list, v: float) -> float:
            for (v0, a), (v1, b) in zip(pts, pts[1:]):
                if v <= v1:
                    return a + (b - a) * _smooth(v0, v1, v) if v >= v0 else a
            return pts[-1][1]
        g = self.eye_gap
        if t:
            lit_edge = [(0.0, -4.0), (0.3, -4.0), (0.42, -g - 3.0), (0.55, -g - 3.0), (0.66, -g + 0.5),
                        (0.8, -g + 2.0), (1.0, -5.0)]
            far_in = [(0.0, 4.5), (0.4, 4.0), (0.5, 3.0), (0.62, 5.0), (0.8, 4.2), (1.0, 3.0)]
        else:
            lit_edge = [(0.0, -5.0), (0.3, -5.0), (0.42, -g - 3.0), (0.55, -g - 3.0), (0.66, -g + 1.5),
                        (0.8, -g + 2.5), (1.0, -5.0)]
            far_in = [(0.0, 5.0), (0.4, 4.6), (0.5, 3.6), (0.62, 5.6), (0.8, 4.6), (1.0, 3.5)]
        for y, (l, r) in self.rows.items():
            v = (y + 0.5 - self.top) / H
            le = self.fx + lerp(lit_edge, v)
            fe = r - lerp(far_in, v)
            for x in range(int(l) - 1, int(r) + 2):
                if not (l <= x + 0.5 <= r):
                    continue
                xc = x + 0.5
                tone = 4 if xc < le and (v < 0.42 or v > 0.5) else 3
                if tone == 4 and xc > le - 3.5 and (x + y) % 2:
                    tone = 3                                     # el paso de la luz a la media tinta, tramado y ancho
                if xc > fe:
                    tone = 2
                elif xc > fe - 2.5 and (x + y) % 2 and v > 0.3:
                    tone = 2                                     # y el de la media tinta a la sombra
                    
                if xc > r - 1.2 and v > 0.45:
                    tone = 1 if v > 0.6 else 2                   # el borde lejano, del lado de la sombra
                if v > 0.93:
                    tone = min(tone, 2)                          # bajo la mandíbula
                if t and xc < l + 1.3 and v > 0.3:
                    tone = 3                                     # la nuca/el costado que se va
                if v < 0.08:
                    tone = min(tone, 3)
                self.put(x, y, "skin", tone)
        # brillos: frente, pómulo cercano, mentón
        fxh = self.fx - (5 if t else 4)
        fyh = self.top + H * 0.22
        for y in range(int(fyh - 3), int(fyh + 4)):
            for x in range(int(fxh - 5), int(fxh + 5)):
                if ((x + 0.5 - fxh) / 4.5) ** 2 + ((y + 0.5 - fyh) / 2.6) ** 2 <= 1:
                    self.shift(x, y, +1, "skin")
        ncx = self.eye_pos_guess()
        cyh = self.ey + self.eye_h + 3
        for y in range(cyh - 1, cyh + 2):
            for x in range(int(ncx - 3), int(ncx + 3)):
                if ((x + 0.5 - ncx) / 3.2) ** 2 + ((y + 0.5 - cyh) / 1.5) ** 2 <= 1 and self.tone_at(x, y) >= 4:
                    self.put(x, y, "skin", 5)
        # la mandíbula proyecta sombra sobre el cuello
        for x in range(SIZE):
            for y in range(self.chin + 1, self.chin + 7):
                if self.is_(x, y, "skin") and not self.in_head(x, y):
                    if any(self.in_head(x, yy) for yy in range(y - 7, y)):
                        self.put(x, y, "skin", 1 if y <= self.chin + 3 else 2)
        for x in range(SIZE):                                   # bajo el mentón, la última fila en sombra
            if self.in_head(x, self.chin) and self.is_(x, self.chin, "skin"):
                self.put(x, self.chin, "skin", 1 if self.tone_at(x, self.chin) <= 2 else 2)
        # bajo el pómulo lejano, la sombra se mete en la mejilla
        far_cheek = self.fx + (g * 0.8 if t else g) + 3.5
        for i in range(7):
            for k in range(2):
                self.shift(far_cheek - i * 0.35 - k, self.ey + 6 + i, -1 if self.tone_at(far_cheek - i * 0.35 - k,
                                                                                          self.ey + 6 + i) >= 3 else 0,
                           "skin")

    def eye_pos_guess(self) -> float:
        g = self.eye_gap
        return self.X(-g * 0.95) if self.t else self.X(-g)

    def ears(self) -> None:
        """Orejas: un óvalo con el borde (hélix) con luz, la concha honda y el lóbulo; de 3/4 se ve una sola."""
        ey = self.ey
        sides = [-1, 1] if not self.t else [-1]
        top, bot = ey - 2, ey + self.nose_len - 1
        cy = (top + bot) / 2
        ry = (bot - top) / 2 + 0.5
        self.ear_pos = []
        if self.hair == "long" and self.hat != "scarf" or self.hat == "scarf":
            for side in sides:
                l, r = self.rows[ey]
                self.ear_pos.append(((l + 6.5) if self.t else (l if side < 0 else r), side))
            return
        for side in sides:
            l, r = self.rows[ey]
            if self.t:
                ex, rx = l + 6.5, 3.0                            # de 3/4, la oreja está corrida hacia la nuca
            else:
                ex, rx = (l - 0.6, 2.4) if side < 0 else (r + 0.6, 2.4)
            self.ear_pos.append((ex, side))
            for y in range(int(top), int(bot) + 1):
                for x in range(int(ex - rx - 1), int(ex + rx + 2)):
                    dx, dy = (x + 0.5 - ex) / rx, (y + 0.5 - cy) / ry
                    if dy < 0:
                        d = dx * dx + dy * dy
                    else:
                        d = (dx * (1 + 0.25 * dy)) ** 2 + dy * dy      # se angosta hacia el lóbulo
                    if d > 1:
                        continue
                    if not self.t and self.in_head(x, y) and abs(dx) < 0.2:
                        continue
                    back = dx < 0 if (self.t or side < 0) else dx > 0
                    tone = 4 if back else 3
                    if d > 0.6:
                        tone = 5 if back and dy < 0.3 else 3       # el hélix
                    if d > 0.8 and not back:
                        tone = 2
                    inner = ((x + 0.5 - (ex + 0.6 * (1 if back else -1) * -1)) / (rx * 0.45)) ** 2 + \
                        ((y + 0.5 - (cy - 0.5)) / (ry * 0.5)) ** 2
                    if inner < 1:
                        tone = 2 if inner < 0.5 else 3             # la concha
                    if dy > 0.62:
                        tone = 4 if back else 3                    # el lóbulo
                    if side > 0 and not self.t:
                        tone = max(1, tone - 1)
                    self.put(x, y, "skin", tone)
            if self.t:                                           # el trago y la sombra donde la oreja toca la cara
                fx_ = ex + rx - 0.5
                for y in range(int(cy - 1), int(cy + 2)):
                    self.put(fx_, y, "skin", 3)
                for y in range(int(top + 1), int(bot)):
                    self.shift(ex + rx + 0.8, y, -1, "skin")
        if "earrings" in self.f["props"]:
            for ex, side in self.ear_pos:
                x = ex + (0.5 if self.t else 0)
                self.put(x, bot + 1, "gold", 5)
                self.put(x, bot + 2, "gold", 3)
                self.put(x, bot + 3, "gold", 4)
                self.put(x, bot + 4, "gold", 2)

    # pelo -------------------------------------------------------------------
    def hair_tone(self, x: int, y: int, cx: float, cy: float, r: float, ox: float, oy: float,
                  clumps: float = 6.0) -> int:
        """Tono de un pixel de pelo: volumen de la bola, mechones que nacen de (ox, oy) y el brillo en franja."""
        u = (x + 0.5 - cx) / r
        v = (y + 0.5 - cy) / r
        nz = math.sqrt(max(0.05, 1 - min(0.95, u * u + v * v)))
        t = self.lit(u, v, nz, -0.02)
        ang = math.atan2(x + 0.5 - ox, y + 0.5 - oy)
        a = ang * clumps + math.sin((y - oy) * 0.35 + self.seed) * 0.35
        idx = math.floor(a)
        frac = a - idx
        off = (_hash(int(idx), 7, self.seed) - 0.5) * 1.2
        t = int(round(t + off))
        if frac < 0.16:
            t -= 1                                             # la raya entre mechón y mechón
        elif 0.4 < frac < 0.7:
            dist = math.hypot(x + 0.5 - ox, y + 0.5 - oy)
            band = r * 0.62
            if abs(dist - band) < 2.2 and t >= 3:
                t += 1                                         # el brillo del mechón
        return max(1, min(5, t))

    def _in_skull(self, x: float, y: float, vol: float) -> bool:
        cy = self.top + self.H * 0.5
        rx = self.W + vol + 0.4
        ry = self.H * 0.5 + vol
        cxs = self.cxh - self.t * 1.2
        if y > cy:
            return False
        dx = (x + 0.5 - cxs) / rx
        dy = (y + 0.5 - cy) / ry
        return abs(dx) ** 2.3 + abs(dy) ** 2.3 <= 1.0

    def hairline(self, x: float) -> float:
        """Altura del nacimiento del pelo en la frente para la columna x."""
        base = self.top + self.H * (0.25 + 0.03 * self.child)
        rel = (x + 0.5 - self.fx) / self.W
        y = base + 2.2 * rel * rel
        if self.hair in ("short", "cropped") and not self.female:
            if self.child > 0.3:                               # flequillo de chico
                y = base + 4 + 1.2 * math.sin(x * 1.3)
            elif self.age >= 50:                               # entradas
                y -= 3.0 * _smooth(0.15, 0.6, abs(rel)) - 1.0
        elif self.hair == "slick":
            y = base - 1.5 + 1.8 * rel * rel
            if self.age >= 50:
                y -= 2.4 * _smooth(0.2, 0.6, abs(rel))
        elif self.hair in ("bun", "braids", "long"):           # raya y el pelo hacia los costados
            y = base - 0.5 + 5.0 * rel * rel
            if self.child > 0.3:
                y = base + 3
        return y

    def back_hair(self) -> None:
        if self.hat == "scarf":
            return
        cx = self.cxh - self.t * 1.4
        cy = self.top + self.H * 0.42
        r = self.W + 3
        if self.hair == "long":
            bottom = self.chin + 22
            for y in range(int(cy), bottom):
                for x in range(SIZE):
                    dx = x + 0.5 - cx
                    reach = r + 2.0 + max(0, y - self.chin + 4) * 0.25
                    if abs(dx) > reach:
                        continue
                    jag = (_hash(x // 3, 1, self.seed) * 5)
                    if y > bottom - 6 + jag - 3:
                        continue
                    t = self.hair_tone(x, y, cx, cy, r + 6, cx + 2, self.top - 6, 5) - 1
                    self.put(x, y, "hair", max(1, t))
        if self.hair == "bun":
            if self.t:
                bx, by = self.cxh - self.W + 1, self.top + 9
            else:
                bx, by = self.cxh, self.top - 1
            br = 7.0 if not self.t else 7.5
            for y in range(int(by - br - 1), int(by + br + 1)):
                for x in range(int(bx - br - 1), int(bx + br + 2)):
                    dx, dy = (x + 0.5 - bx) / br, (y + 0.5 - by) / (br * 0.88)
                    if dx * dx + dy * dy <= 1:
                        ang = math.atan2(dy, dx)
                        t = self.lit(dx, dy, math.sqrt(max(0.05, 1 - dx * dx - dy * dy)))
                        a = ang * 2.5 + math.hypot(dx, dy) * 5
                        if (a % 2) < 0.45:
                            t -= 1                             # la vuelta del rodete
                        elif t >= 4 and (a % 2) < 1.1:
                            t = 5
                        self.put(x, y, "hair", max(1, t))
            self.bun = (bx, by, br)

    def front_hair(self) -> None:
        if self.hat == "scarf":
            return
        hair = self.hair
        vol = {"cropped": 0.6, "slick": 0.8, "bald": 0.0, "short": 2.2, "long": 2.8, "bun": 1.3,
               "braids": 1.6}.get(hair, 2.0)
        if self.child > 0.3:
            vol += 1.0
        if self.hat not in ("none",):
            vol = min(vol, 1.5)
        cx = self.cxh - self.t * 1.2
        cy = self.top + self.H * 0.5
        r = self.W + 2
        part_dir = -1 if (self.seed % 3) else 1                 # de qué lado va la raya
        if hair in ("bun", "braids", "long"):
            ox = self.fx + (2 if self.seed % 2 else -1) * (1 if self.female else part_dir)
            oy = self.top - 4
        elif hair == "slick":
            ox, oy = self.fx, self.top + self.H * 0.6
        else:
            ox, oy = self.fx + part_dir * self.W * 0.45, self.top - 2
        grey = "grey_temples" in self.f["age_marks"]
        y_from = self.top - int(vol) - 2
        for y in range(y_from, self.ey + 3):
            for x in range(SIZE):
                if not self._in_skull(x, y, vol):
                    continue
                in_face = self.in_head(x, y)
                hl = self.hairline(x)
                l, r_ = self.rows.get(y, (99, -99))
                side_band = 2.6 if hair not in ("cropped", "slick") else 1.8
                if hair in ("long", "bun", "braids"):
                    side_band = 3.8
                near_edge = in_face and (x + 0.5 - l < side_band or r_ - x - 0.5 < side_band * 0.7)
                back = False
                if self.t and in_face:
                    back = x + 0.5 - l < 6.0
                covered = (not in_face) or y < hl or (near_edge and y < self.ey - 3) or (back and y < self.ey + 1)
                if hair == "bald":
                    crown = self.top + self.H * 0.3
                    covered = ((not in_face) and crown < y < self.ey + 1) or \
                              (in_face and (x + 0.5 - l < 2.2 or r_ - x - 0.5 < 1.6) and crown < y < self.ey) or \
                              (back and crown - 1 < y < self.ey + 1)
                if not covered:
                    continue
                if self.hat != "none" and y < self.top + self.H * 0.2:
                    continue
                if hair == "slick":
                    t = self.lit((x + 0.5 - cx) / r, (y + 0.5 - cy) / r, 0.6)
                    k = (y + (x - cx) * 0.18)
                    if int(k) % 3 == 0:
                        t -= 1                                   # las líneas del peine
                    elif t >= 4 and int(k) % 3 == 1:
                        t = 5
                elif hair == "cropped":
                    t = self.lit((x + 0.5 - cx) / r, (y + 0.5 - cy) / r, 0.7)
                    if _hash(x, y, self.seed) < 0.3:
                        t -= 1
                    t = min(t, 4)
                else:
                    t = self.hair_tone(x, y, cx, cy, r, ox, oy, 6.5 if hair == "short" else 5.0)
                mat = "hair"
                if grey and (near_edge or back or y > self.top + self.H * 0.3) and \
                        (x + 0.5 - l < 6.5 or r_ - x - 0.5 < 3) and y > self.top + self.H * 0.18:
                    mat = "grey"
                self.put(x, y, mat, t)
        self.fringe(ox, oy, vol)
        # sombra del pelo sobre la frente
        for x in range(SIZE):
            for y in range(self.top, self.ey):
                if self.is_(x, y, "skin") and self.is_(x, y - 1, "hair", "grey"):
                    self.shift(x, y, -1, "skin")
                    self.shift(x, y + 1, -1 if self.tone_at(x, y + 1) >= 4 else 0, "skin")
                    break
        if hair == "bald":                                     # brillo de la pelada
            hx = self.cxh - 6 - self.t
            for dx, dy, t in ((0, 0, 5), (1, 0, 5), (2, 0, 4), (3, 0, 4), (-1, 1, 4), (0, 1, 5), (1, 1, 4),
                              (-1, 2, 4)):
                self.put(hx + dx, self.top + 4 + dy, "skin", t)
        if "bald_spot" in self.f["age_marks"] and hair != "bald":
            hx = self.cxh - self.t * 3
            for dx in range(-3, 4):
                self.put(hx + dx, self.top - 1, "skin", 4)
                if abs(dx) < 2:
                    self.put(hx + dx, self.top, "skin", 3)
        self.stray_hairs(vol)

    def fringe(self, ox: float, oy: float, vol: float) -> None:
        """Puntas de mechones sobre la frente: el borde del pelo no es una línea recta."""
        hair = self.hair
        if hair in ("bald", "slick", "cropped") or self.hat in ("kepi", "rail_cap", "fedora", "cloche"):
            return
        l, r = self.rows[self.ey - 6]
        n = 0
        x = l + 3
        while x < r - 2:
            hl = self.hairline(x)
            w = 3 + int(_hash(int(x), 2, self.seed) * 2)
            ln = 1 + int(_hash(int(x), 3, self.seed) * (3 if self.child > 0.3 or hair == "short" else 2))
            if hair in ("bun", "braids", "long") and abs(x - ox) < 3:
                x += w
                continue
            lean = 1 if x > ox else -1
            for j in range(ln):
                yy = int(hl) + j
                for i in range(max(1, w - 1 - j)):
                    xx = x + i + lean * j * 0.6
                    if self.is_(xx, yy, "skin"):
                        self.put(xx, yy, "hair", 2 if i else 3)
            if self.is_(x + lean * ln * 0.6, int(hl) + ln, "skin"):
                self.shift(x + lean * ln * 0.6, int(hl) + ln, -1, "skin")
            x += w
            n += 1

    def stray_hairs(self, vol: float) -> None:
        if self.hair in ("bald", "slick", "cropped") or self.hat != "none":
            return
        rr = random.Random(self.seed)
        cx = self.cxh - self.t * 1.2
        for _ in range(3 if self.hair != "short" else 2):
            ang = rr.uniform(-2.4, -0.6)
            r0 = self.W + vol + 0.2
            x0 = cx + math.cos(ang) * r0
            y0 = self.top + self.H * 0.5 + math.sin(ang) * (self.H * 0.5 + vol)
            dx, dy = math.cos(ang + rr.uniform(-0.5, 0.5)), math.sin(ang) * 0.8
            for i in range(rr.randint(2, 4)):
                x, y = x0 + dx * (i + 1) + (0.3 * i * i * rr.choice([-1, 1]) * 0.3), y0 + dy * (i + 1)
                if not self.mat[int(y)][int(x)]:
                    self.put(x, y, "hair", 2)

    def front_long_hair(self) -> None:
        """Pelo largo y trenzas que caen por delante de los hombros."""
        if self.hat == "scarf":
            return
        if self.hair == "long":
            cy = self.top + self.H * 0.42
            for side in (-1, 1):
                if self.t and side > 0:
                    continue
                l, r = self.rows[self.ey]
                edge = l if side < 0 else r
                for y in range(self.ey - 4, self.chin + 20):
                    w = 4.5 + 2.5 * _smooth(self.ey, self.chin + 8, y)
                    for i in range(int(w) + 1):
                        x = edge + side * (1.5 - i) if y < self.chin - 2 else edge + side * (3 - i)
                        if self.in_head(x, y) and i > 1.5:
                            continue
                        jag = _hash(int(x), 9, self.seed) * 6
                        if y > self.chin + 13 + jag:
                            continue
                        t = self.hair_tone(int(x), y, self.cxh, cy, self.W + 6, self.fx, self.top - 12, 5)
                        if side > 0:
                            t = min(t, 3)
                        self.put(x, y, "hair", t)
        if self.hair == "braids":
            for side in ((-1, 1) if not self.t else (-1, 1)):
                l, r = self.rows[self.ey + 4]
                edge = (l if side < 0 else r) - side * 2
                if self.t and side > 0:
                    edge = r - 1
                for i, y in enumerate(range(self.ey + 4, self.chin + 24)):
                    x = edge + side * (0.5 * math.sin(i * 0.4))
                    seg = i % 4
                    w = 5 if seg in (1, 2) else 4
                    for j in range(w):
                        rel = j / (w - 1)
                        t = 4 if rel < 0.3 else 3 if rel < 0.7 else 2
                        if seg == 0:
                            t -= 1
                        if seg == 1 and j == 1 + (i // 4) % 2:
                            t = 5
                        if side > 0 and self.t:
                            t -= 1
                        self.put(x + j - 2, y, "hair", t)
                    self.put(x - 2 + (seg % 2) * (w - 1), y, "hair", 1)
                yb = self.chin + 24
                for j in range(4):
                    self.put(edge + j - 2, yb, "red", 3 if j < 2 else 2)
                    self.put(edge + j - 2, yb + 1, "red", 2 if j < 2 else 1)
                for j in range(3):
                    self.put(edge + j - 1, yb + 2, "hair", 3)
                    self.put(edge + j - 1 + (j - 1) * 0.5, yb + 3, "hair", 2)

    # rasgos ------------------------------------------------------------------
    def features(self) -> None:
        g = self.eye_gap
        if self.t:
            near = (self.X(-g * 0.95), self.eye_w, -1, False)
            far = (self.X(g * 0.72 + 0.2), self.eye_w - 2, 1, True)
            self.eye_pos = [near, far]
        else:
            self.eye_pos = [(self.X(-g), self.eye_w, -1, False), (self.X(g), self.eye_w, 1, False)]
        self.sockets()
        self.nose()
        for cx, w, outer, far in self.eye_pos:
            self.eye(cx, w, outer, far)
        self.brows()
        self.mouth()
        self.cheeks()
        self.age_marks()
        self.marks()

    def sockets(self) -> None:
        """Cuencas: sombra entre la ceja y el ojo junto al puente de la nariz, y el lado lejano."""
        ey = self.ey
        for cx, w, outer, far in self.eye_pos:
            inner_x = cx - outer * (w / 2)
            for dy in range(-3, 1):
                for i in range(3):
                    self.shift(inner_x - outer * (i - 1), ey + dy, -1, "skin")

    def eye(self, cx: float, w: int, outer: int, far: bool) -> None:
        f = self.f
        kind, expr = f["eyes"], f["expression"]
        h = self.eye_h
        y0 = self.ey
        x0 = int(round(cx - w / 2))
        tilt = self.tilt
        ups, los = {}, {}
        for i in range(w):
            x = x0 + i
            s = (i + 0.5) / w
            si = s if outer > 0 else 1 - s                      # 0 junto a la nariz, 1 en la comisura de afuera
            peak = 0.45
            a = 1 - ((si - peak) / (peak if si < peak else 1 - peak)) ** 2
            u = y0 + (1 - a) * 1.8 - tilt * (si - 0.5) * 1.6
            lo = y0 + h - (1 - a) * 1.4 - tilt * (si - 0.5) * 0.6
            if kind in ("tired", "hooded") or expr in ("tired", "sad"):
                u += 0.5 * _smooth(0.2, 0.8, si)               # el párpado cae hacia afuera
            if expr in ("stern",) or kind == "narrow":
                u += 0.8 * (1 - _smooth(0.0, 0.6, si))         # el párpado baja junto a la nariz
            if expr in ("worried", "nervous") and kind != "narrow":
                u -= 0.6 * (1 - si)
            if expr in ("kind",) or f["mouth"] == "smile":
                lo -= 0.9 * math.sin(math.pi * si)             # el ojo que sonríe: el párpado de abajo sube
            if expr == "sly":
                lo -= 0.7 * math.sin(math.pi * si)
            u, lo = int(round(u)), int(round(lo))
            if lo - u < 2:
                lo = u + 2 if 0.15 < si < 0.85 else u + 1
            ups[x], los[x] = u, lo
        mid = sorted(ups.values())[0]
        # piel del párpado: luz arriba del ojo, el pliegue y la cuenca
        crease = 2 if kind not in ("hooded",) and self.age < 55 else 1
        for x in ups:
            s = (x - x0 + 0.5) / w
            si = s if outer > 0 else 1 - s
            u = ups[x]
            if 0.08 < si < 0.95:
                self.put(x, u - crease - 1, "skin", 2 if not far else 1)             # el pliegue
                if crease == 2:
                    self.put(x, u - 2, "skin", 4 if not far else 3)
                self.put(x, u - 1, "skin", 3 if not far else 2)
            if kind == "hooded" and si > 0.45:
                self.put(x, u - 1, "skin", 2)
        # blanco del ojo
        for x in ups:
            s = (x - x0 + 0.5) / w
            si = s if outer > 0 else 1 - s
            for y in range(ups[x] + 1, los[x]):
                t = 4 if not far else 3
                if y == ups[x] + 1:
                    t -= 2                                       # la sombra del párpado sobre el ojo
                if si < 0.12 or si > 0.88:
                    t = min(t, 3 if not far else 2)
                self.put(x, y, "eyew", t)
        # iris, pupila y brillo
        gaze = (-0.6 if self.t else 0.0) + (0.4 if far else 0)
        icx = cx + gaze
        top_open = min(ups.values()) + 1
        icy = top_open + (max(los.values()) - top_open) / 2 + 0.3
        ir = 2.6 if w >= 9 else 2.2
        if self.child > 0.5:
            ir += 0.4
        if far:
            ir -= 0.3
        for x in ups:
            for y in range(ups[x] + 1, los[x]):
                dx, dy = (x + 0.5 - icx) / ir, (y + 0.5 - icy) / (ir * 1.05)
                d2 = dx * dx + dy * dy
                if d2 > 1.0:
                    continue
                t = 3
                if y <= ups[x] + 1:
                    t = 1                                        # bajo el párpado, el iris en sombra
                elif y <= ups[x] + 2:
                    t = 2
                elif y >= los[x] - 1:
                    t = 4                                        # abajo el iris se aclara
                if d2 > 0.62 and abs(dx) > 0.7:
                    t = min(t, 1)                                # el anillo del iris
                if far:
                    t = max(1, t - 1)
                self.put(x, y, "iris", t)
        for x in ups:
            for y in range(ups[x] + 1, los[x]):
                if abs(x + 0.5 - icx) < 1.0 and abs(y + 0.5 - (icy - 0.2)) < 1.0:
                    self.put(x, y, "iris", 0)                   # pupila
        hx, hy = int(math.floor(icx - 1.2)), int(math.floor(icy - 1.2))
        if hy <= ups.get(hx, hy):
            hy = ups.get(hx, hy) + 1
        if self.is_(hx, hy, "iris") or self.is_(hx, hy, "eyew"):
            self.put(hx, hy, "eyew", 5)                         # brillo
            if not far and w >= 9 and self.eye_h >= 4 and self.is_(hx + 1, hy, "iris"):
                self.put(hx + 1, hy, "eyew", 5 if self.child > 0.3 or self.female else 4)
        lx, ly = int(math.floor(icx + 1)), int(math.floor(icy + 1))
        if self.is_(lx, ly, "iris"):
            self.put(lx, ly, "iris", 5)
        # párpado de arriba: la línea de las pestañas, más gruesa hacia afuera
        lashy = self.female or self.child > 0.4
        for x in ups:
            s = (x - x0 + 0.5) / w
            si = s if outer > 0 else 1 - s
            u = ups[x]
            self.put(x, u, "lash", 1 if si > 0.15 else 2)
            if si > 0.55 and (lashy or si > 0.8):
                self.put(x, u - 1 if lashy else u, "lash", 0 if lashy else 1)
        ox = x0 - 1 if outer < 0 else x0 + w                       # comisura de afuera
        oy = ups[x0 if outer < 0 else x0 + w - 1]
        self.put(ox, oy + 1, "lash", 1)
        if lashy:
            self.put(ox, oy, "lash", 0)
            self.put(ox + outer, oy - 1, "lash", 1)
        ix = x0 + w if outer < 0 else x0 - 1                       # lagrimal
        iy = (ups[x0 + w - 1 if outer < 0 else x0] + los[x0 + w - 1 if outer < 0 else x0]) // 2
        self.put(ix, iy, "lip", 3)
        self.put(ix, iy - 1, "skin", 2)
        # párpado de abajo
        for x in los:
            s = (x - x0 + 0.5) / w
            si = s if outer > 0 else 1 - s
            lo = los[x]
            if 0.1 < si:
                self.put(x, lo, "skin", 2 if si > 0.3 else 3)
                if lashy and si > 0.6:
                    self.put(x, lo, "lash", 3)
            if 0.2 < si < 0.85 and self.age < 50:
                self.shift(x, lo + 1, +1, "skin")                 # la luz del párpado de abajo
        if kind == "tired" or "eye_bags" in self.f["age_marks"]:
            for x in los:
                s = (x - x0 + 0.5) / w
                si = s if outer > 0 else 1 - s
                if 0.1 < si < 0.95:
                    yb = los[x] + 2 + (1 if 0.3 < si < 0.75 else 0)
                    self.put(x, yb, "skin", 2)
                    self.tint(x, los[x] + 1, (110, 70, 100), 0.18, "skin")
        self.eye_box = getattr(self, "eye_box", []) + [(x0, w, mid, max(los.values()), outer, far)]

    def brows(self) -> None:
        f = self.f
        style = f["brows"]
        expr = f["expression"]
        ti, to, ah, ap, io = BROWS.get(style, BROWS["thick"])
        if self.child > 0.4 or (self.female and style in ("thick", "bushy")):
            ti, to = min(ti, 2), min(to, 1)
        if expr in ("worried", "sad", "nervous") and style != "worried":
            io -= 1.6
            ah *= 0.6
        if expr == "stern" and style != "furrowed":
            io += 1.4
        if expr == "kind":
            io -= 0.5
        if expr == "proud":
            ah += 0.5
        for idx, (cx, w, outer, far) in enumerate(self.eye_pos):
            by = self.ey - self.brow_h
            L = w + 3 if not far else w + 1
            inner_x = cx - outer * (w / 2 + 1.0)
            lift = 0.0
            if style == "sly" or expr == "sly":
                lift = 1.6 if idx == 1 else 0.0
            for i in range(L):
                s = i / max(1, L - 1)
                x = inner_x + outer * i
                arch = 1 - ((s - ap) / max(ap, 1 - ap)) ** 2
                y = by - ah * arch + io * (1 - s) * 0.9 - lift + (0.6 * s if far else 0)
                thick = int(round(ti + (to - ti) * s))
                if i == L - 1:
                    thick = max(1, thick - 1)
                yi = int(round(y))
                for j in range(thick):
                    t = 2 if j < thick - 1 else 1
                    if j == 0 and i < L - 2:
                        t = 3                                    # el borde de arriba, con luz
                    if style in ("bushy", "thick") and (i + j * 2) % 3 == 0:
                        t = max(1, t - 1)                        # los pelos de la ceja
                    if far:
                        t = max(1, t - 1)
                    self.put(x, yi + j, "brow", t)
                if style == "bushy" and _hash(int(x), yi, self.seed) < 0.45:
                    self.put(x + outer * 0.5, yi - 1, "brow", 2)
                self.shift(x, yi + thick, -1, "skin")           # la cuenca bajo la ceja
            if style == "bushy":                                  # pelos sueltos hacia arriba en la punta de adentro
                self.put(inner_x - outer, by + io * 0.9 - 1, "brow", 1)
            if (f["brows"] == "furrowed" or expr in ("stern", "worried")) and outer < 0:
                gx = self.fx - 1.0 + (0.6 if self.t else 0)
                y1 = by + io * 0.9 - (2 if expr == "worried" else 0)
                for dy in range(0, 3 if self.age < 40 else 4):
                    self.put(gx + dy * 0.25, y1 + dy, "skin", 2)
                    self.shift(gx - 1 + dy * 0.25, y1 + dy, +1, "skin")
        if "scar_brow" in self.f["marks"]:
            cx, w, outer, far = self.eye_pos[1 if self.t else 0]
            sx = cx + 1
            for y in range(int(self.ey - self.brow_h - 4), self.ey - 1):
                if self.is_(sx, y, "brow", "skin"):
                    self.put(sx, y, "skin", 5)
                    self.put(sx + 1, y, "skin", 2)

    def nose(self) -> None:
        f = self.f
        kind = f["nose"]
        t = self.t
        ey = self.ey
        tip_y = ey + self.nose_len
        crooked = kind == "crooked" or "broken_nose" in f["marks"]
        broad = 1 if kind == "broad" else 0
        if t:
            bx, tip = self.X(0.6), self.X(3.2 + (0.6 if kind in ("long", "hooked") else 0) - (0.8 if kind == "button" else 0))
        else:
            bx = tip = self.fx
        # el puente: luz del lado de la luz, sombra del otro (el perfil de la nariz de 3/4)
        for y in range(ey + 1, tip_y):
            q = (y - ey) / max(1, tip_y - ey)
            x = bx + (tip - bx) * q
            if crooked and q > 0.45:
                x += 1
            if kind == "hooked" and 0.3 < q < 0.75:
                x += 0.8 * math.sin(math.pi * (q - 0.3) / 0.45) * (1 if t else 0.4)
            if 0.3 < q < 0.9:
                self.put(x - 1, y, "skin", 4 if q < 0.75 else 5)
            if t:
                if q > 0.35:
                    self.put(x + 1, y, "skin", 2 if q < 0.75 else 1)
            else:
                if q > 0.3:
                    self.put(x + 1, y, "skin", 2 if q > 0.55 else 3)
            if crooked and 0.4 < q < 0.5:
                self.put(x, y, "skin", 2)                        # el quiebre
        # punta, aletas y fosas
        tx = tip + (1 if crooked else 0)
        ty = tip_y
        self.put(tx - 1, ty - 1, "skin", 5)
        self.put(tx, ty - 1, "skin", 4)
        self.put(tx - 1, ty, "skin", 4)
        self.put(tx, ty, "skin", 3)
        self.put(tx + 1, ty - 1, "skin", 2 if t else 3)
        self.put(tx + 1, ty, "skin", 1 if t else 2)
        if kind == "button":
            self.put(tx - 2, ty - 1, "skin", 4)
            self.put(tx, ty - 2, "skin", 4)
        if kind in ("broad",) or self.build > 0:
            self.put(tx - 2, ty, "skin", 4)
        # aleta del lado cercano: una curva en sombra y la fosa
        ax = tx - 4 - broad
        for dx, dy, tt in ((0, -1, 2), (0, 0, 2), (1, 1, 1), (-1, 0, 3) if not t else (-1, -1, 3)):
            self.put(ax + dx, ty + dy, "skin", tt)
        self.put(ax + 1, ty - 1, "skin", 4)
        self.put(tx - 2 - broad, ty + 1, "skin", 0)
        self.put(tx - 1 - broad, ty + 1, "skin", 1)
        if broad:
            self.put(tx - 1, ty + 1, "skin", 1)
        if t:                                                   # la fosa lejana apenas asoma
            self.put(tx + 1, ty + 1, "skin", 1)
            self.put(tx + 2, ty, "skin", 2)
        else:
            self.put(tx + 1 + broad, ty + 1, "skin", 0)
            self.put(tx + broad, ty + 1, "skin", 1)
            bx2 = tx + 3 + broad
            for dx, dy, tt in ((0, -1, 2), (0, 0, 1), (-1, 1, 1)):
                self.put(bx2 + dx, ty + dy, "skin", tt)
        # sombra bajo la nariz
        for dx in range(-3 - broad, 3):
            self.shift(tx + dx, ty + 2, -1, "skin")
        if "nose_red" in self.ex:
            for dx, dy in ((0, -1), (-1, -1), (0, 0), (1, -1), (-1, 0), (-2, 0), (-1, -2), (1, 0), (-3, -1)):
                self.tint(tx + dx, ty + dy, (205, 70, 64), 0.4, "skin")
        self.tip = (tx, ty)

    def mouth(self) -> None:
        f = self.f
        kind = f["mouth"]
        tip, tip_y = self.tip
        my = tip_y + self.mouth_gap
        self.my = my
        t = self.t
        mx = (self.X(1.4) if t else self.fx)
        hw = self.mouth_w
        x0 = int(round(mx - hw * (1.1 if t else 1)))
        x1 = int(round(mx + hw * (0.7 if t else 1)))
        self.mx = mx
        self.mouth_x = (x0, x1)
        lip = self.female and self.child < 0.5
        cl = cr = 0
        if kind in ("smile", "neutral", "full"):
            cl = cr = -1                                         # las comisuras, apenas para arriba: no todos tristes
        elif kind == "frown":
            cl = cr = 1
        elif kind == "smirk":
            cr = -1
        # la línea entre los labios
        for x in range(x0, x1 + 1):
            y = my
            if x - x0 < 1.5 and cl:
                y += cl
            if x1 - x < 1.5 and cr:
                y += cr
            end = x in (x0, x1)
            self.put(x, y, "lip", 1 if end else 0)
            if kind == "smile" and x0 + 1 < x < x1 - 1:
                self.put(x, y + 1, "lip", 1)
        # labio de arriba (en sombra: mira para abajo) y labio de abajo (con luz)
        for x in range(x0 + 1, x1):
            rel = (x + 0.5 - mx) / hw
            self.put(x, my - 1, "lip", 2 if lip else 3 if rel < -0.3 else 2)
            if lip and kind != "thin" and abs(rel) < 0.7:
                self.put(x, my - 2, "lip", 3 if abs(rel) > 0.15 else 4)     # el arco de cupido
        if not lip:
            for x in range(x0 + 1, x1):
                self.tint(x, my - 1, self.R["skin"][2], 0.4, "lip")
        low = 2 if (lip and kind in ("full", "neutral", "smile")) else 1
        if kind == "thin":
            low = 1
        for j in range(low):
            for x in range(x0 + 1 + j, x1 - j):
                rel = (x + 0.5 - mx) / hw
                tt = 4 if rel < -0.1 else 3
                if j == low - 1 and low > 1:
                    tt -= 1
                if kind == "smile":
                    tt = 4 if rel < 0 else 3
                self.put(x, my + 1 + j + (1 if kind == "smile" else 0), "lip" if lip or not j else "skin", tt)
        if not lip:
            for x in range(x0 + 1, x1):
                self.tint(x, my + 1 + (1 if kind == "smile" else 0), self.R["skin"][4], 0.35, "lip")
        hl = int(mx - hw * 0.35)
        self.put(hl, my + 1 + (1 if kind == "smile" else 0), "lip", 5 if lip else 4)
        under = my + 1 + low + (1 if kind == "smile" else 0)
        for x in range(int(mx - hw * 0.6), int(mx + hw * 0.5)):
            self.shift(x, under, -1, "skin")                     # sombra bajo el labio
        if kind == "bite":                                       # se muerde el labio: el diente sobre el de abajo
            self.put(mx - 1, my + 1, "eyew", 4)
            self.put(mx, my + 1, "eyew", 3)
        if kind == "smile":                                       # los pliegues de la sonrisa
            self.put(x0 - 1, my - 2, "skin", 2)
            self.put(x0 - 1, my - 1, "skin", 2)
            self.put(x1 + 1, my - 2, "skin", 2)
        if kind == "frown":
            self.put(x0 - 1, my + 2, "skin", 2)
            self.put(x1 + 1, my + 2, "skin", 2)
        if kind == "smirk":
            self.put(x1 + 1, my - 2, "skin", 2)
        # filtrum
        for y in range(tip_y + 3, my - 1 - (1 if lip else 0)):
            self.shift(mx - 1, y, +1, "skin")
            self.shift(mx + 1, y, -1, "skin")
        # mentón: luz y hoyuelo
        cy = self.chin - 4
        for dx, dy in ((-2, 0), (-1, 0), (-2, 1), (-1, -1)):
            self.shift(mx + dx, cy + dy, +1, "skin")
        if f["jaw"] == "strong" and not self.female:
            self.put(mx, cy + 1, "skin", 2)
            self.put(mx, cy + 2, "skin", 2)
        # la quijada: una línea de sombra que la marca en las caras fuertes y flacas
        if f["jaw"] == "strong" or f["shape"] in ("square", "gaunt"):
            for y in range(my, self.chin - 1):
                l, r = self.rows[y]
                self.shift(l + 2.5, y, -1, "skin")
                self.shift(r - 2.0, y, -1, "skin")

    def cheeks(self) -> None:
        kind = self.f["cheeks"]
        ey = self.ey
        for cx, w, outer, far in self.eye_pos:
            ccx = cx + outer * 1.5
            ccy = ey + 7
            if kind in ("blush", "ruddy"):
                amt = 0.28 if kind == "blush" else 0.36
                rx, ry = (4.5, 2.4) if kind == "blush" else (5.5, 3.2)
                for y in range(int(ccy - ry), int(ccy + ry) + 1):
                    for x in range(int(ccx - rx), int(ccx + rx) + 1):
                        d = ((x + 0.5 - ccx) / rx) ** 2 + ((y + 0.5 - ccy) / ry) ** 2
                        if d <= 1:
                            self.tint(x, y, (214, 92, 92), amt * (1 - d * 0.6) * (0.7 if far else 1), "skin")
                if self.child > 0.3 or self.female:
                    self.tint(ccx - 1, ccy - 1, (255, 255, 255), 0.25, "skin")
            if kind == "hollow" or self.f["shape"] == "gaunt":
                for dy in range(5, 13):
                    self.shift(ccx + outer * 2.4 - outer * dy * 0.25, ey + dy, -1, "skin")
                    if not far:
                        self.shift(ccx + outer * 3.4 - outer * dy * 0.25, ey + dy, -1, "skin")

    def age_marks(self) -> None:
        am = self.f["age_marks"]
        ey = self.ey
        if "wrinkles_forehead" in am:
            for row, dy in enumerate((-self.brow_h - 5, -self.brow_h - 8, -self.brow_h - 11)):
                if row == 2 and self.age < 60:
                    continue
                for dx in range(-8, 8):
                    if _hash(dx, row, self.seed) < 0.18:
                        continue
                    x = self.fx + dx
                    y = int(ey + dy + 0.03 * dx * dx)
                    if self.is_(x, y, "skin") and self.tone_at(x, y) >= 3:
                        self.shift(x, y, -1, "skin")
                        self.shift(x, y - 1, +1, "skin")
        if "crow_feet" in am:
            for cx, w, outer, far in self.eye_pos:
                ox = cx + outer * (w / 2 + 1.5)
                for k, (dx, dy) in enumerate(((0, 0), (1, -1), (0, 2), (1, 3), (1, 1))):
                    self.shift(ox + outer * dx, ey + dy, -1, "skin")
        if "nasolabial" in am or self.f["mouth"] == "smile":
            tip, tip_y = self.tip
            x0, x1 = self.mouth_x
            pts = [(tip - 5.5, tip_y), (x0 - 2.0, self.my - 1), (x0 - 1.5, self.my + 2)]
            self.line(pts, "skin", 2, ("skin",))
            for (x, y) in ((tip - 6.5, tip_y + 1), (x0 - 3, self.my - 1)):
                self.shift(x, y, +1, "skin")
            if not self.t:
                self.line([(tip + 5.5, tip_y), (x1 + 2.0, self.my - 1), (x1 + 1.5, self.my + 2)], "skin", 2,
                          ("skin",))
        if "jowls" in am:
            x0, x1 = self.mouth_x
            for side in (-1, 1):
                if side > 0 and self.t:
                    continue
                xs = (x0 - 3) if side < 0 else (x1 + 3)
                self.line([(xs, self.my + 2), (xs - side * 0.5, self.my + 5), (xs + side * 1.5, self.chin - 2)],
                          "skin", 2, ("skin",))
        if "eye_bags" in am and self.age >= 60:
            for cx, w, outer, far in self.eye_pos:
                self.shift(cx, ey + self.eye_h + 3, -1, "skin")

    def marks(self) -> None:
        mk = self.f["marks"]
        ey = self.ey
        near_cx = self.eye_pos[0][0]
        if "stubble" in mk:
            tip, tip_y = self.tip
            for y in range(tip_y + 1, self.chin + 1):
                l, r = self.rows[y]
                for x in range(int(l), int(r) + 1):
                    if not self.is_(x, y, "skin") or not self.in_head(x, y):
                        continue
                    lipzone = abs(x + 0.5 - self.mx) < self.mouth_w - 1 and self.my - 1 <= y <= self.my + 2
                    if lipzone:
                        continue
                    jaw = y > self.my + 2 or abs(x + 0.5 - self.mx) > self.mouth_w + 1 or y < self.my - 1
                    side_ok = y > ey + 7 and (x + 0.5 - l < 6 or r - x - 0.5 < 5 or jaw)
                    if side_ok and (jaw or y > ey + 8):
                        self.mat[y][x] = "stubble"
                        if _hash(x, y, self.seed) < 0.3:
                            self.tone[y][x] = max(1, self.tone[y][x] - 1)
        if "scar_cheek" in mk:
            sx = near_cx - 2
            for i in range(9):
                x, y = sx + i * 0.55, ey + 4 + i
                self.put(x, y, "skin", 5)
                self.put(x + 1, y, "skin", 1 if i % 2 else 2)
        if "mole" in mk:
            x0, x1 = self.mouth_x
            mx = x1 + 2 if self.seed % 2 else x0 - 3
            self.put(mx, self.my - 3, "lash", 2)
        rr = random.Random(self.seed)
        if "freckles" in mk:
            for _ in range(16):
                x = self.fx + rr.uniform(-10, 8)
                y = ey + rr.uniform(4, 10)
                if abs(x - self.tip[0]) > 1.5 or y < ey + 6:
                    self.tint(x, y, (170, 90, 52), rr.uniform(0.15, 0.28), "skin")
        if "pockmarks" in mk:
            for _ in range(16):
                x = near_cx + rr.uniform(-4, 4)
                y = ey + rr.uniform(5, 13)
                self.shift(x, y, -1 if rr.random() < 0.6 else 1, "skin")
        if "soot" in self.ex:
            for _ in range(22):
                x = near_cx + rr.uniform(-6, 4)
                y = ey + rr.uniform(5, 14)
                self.tint(x, y, (40, 34, 30), rr.uniform(0.15, 0.3), "skin", "stubble")
            for _ in range(8):
                self.tint(self.fx + rr.uniform(-7, 2), ey - self.brow_h - rr.uniform(3, 7), (40, 34, 30), 0.35, "skin")
        if "pale" in self.ex:
            for cx, w, outer, far in self.eye_pos:
                for dx in range(-3, 3):
                    self.tint(cx + dx, ey + self.eye_h + 1, (110, 90, 130), 0.3, "skin")

    def facial_hair(self) -> None:
        if "beard" in self.ex:
            self.beard()
        if "mustache" in self.ex:
            self.mustache(self.f.get("mustache", "brush"))

    def mustache(self, style: str) -> None:
        my, mx = self.my, self.mx
        x0, x1 = self.mouth_x
        tip, tip_y = self.tip
        hw_l = mx - x0 + 1.5
        hw_r = x1 - mx + 1.5
        top_y = tip_y + 2
        mat = "hair"
        if "grey_temples" in self.f["age_marks"] and self.age >= 50:
            mat = "grey"
        for x in range(int(mx - hw_l - 3), int(mx + hw_r + 4)):
            rel = (x + 0.5 - mx) / (hw_l if x < mx else hw_r)
            a = abs(rel)
            if style == "walrus":
                if a > 1.25:
                    continue
                top = top_y + (1 if a > 0.7 else 0)
                bot = my + 1 + (1 if a > 0.6 else 0) + (1 if a > 0.95 else 0)
            elif style == "handlebar":
                if a > 1.6:
                    continue
                top = top_y + 1 + (1 if a > 0.5 else 0) - (2 if a > 1.25 else 0) - (1 if a > 1.45 else 0)
                bot = my - 1 + (1 if 0.3 < a < 1.0 else 0) - (2 if a > 1.2 else 0)
            elif style == "pencil":
                if a > 1.0:
                    continue
                top = my - 2
                bot = my - 1 if a < 0.9 else my - 2
            else:                                               # brush: el cepillo
                if a > 1.1:
                    continue
                top = top_y + (1 if a > 0.75 else 0)
                bot = my - 1 + (1 if a > 0.85 else 0)
            for y in range(int(top), int(bot) + 1):
                tone = 4 if rel < -0.3 else 3 if rel < 0.3 else 2
                if y == bot:
                    tone -= 1
                if y == top:
                    tone = min(5, tone + 1) if rel < 0 else tone
                if (x + (y if rel < 0 else -y)) % 3 == 0:
                    tone -= 1                                   # los pelos del bigote, hacia afuera
                if abs(rel) < 0.12 and y == top:
                    tone = 1                                    # la raya del medio
                self.put(x, y, mat, max(1, tone))
        if style == "walrus":
            for x in range(x0, x1 + 1):                         # el bigote tapa el labio de arriba
                self.put(x, my + 2, "skin", 2) if self.is_(x, my + 2, "lip") else None

    def beard(self) -> None:
        my, mx = self.my, self.mx
        tip, tip_y = self.tip
        cy = self.top + self.H * 0.5
        length = 4 + int(round(6 * self.old)) + (3 if self.hair == "long" else 0)
        mat = "grey" if self.age >= 60 or "grey_temples" in self.f["age_marks"] else "hair"
        for y in range(self.ey + 7, self.chin + length + 1):
            if y in self.rows:
                l, r = self.rows[y]
            else:
                sh = y - self.chin
                l0, r0 = self.rows[self.chin]
                l, r = l0 - 0.5 + sh * 0.7, r0 + 0.5 - sh * 0.7
                if r - l < 3:
                    continue
            for x in range(int(l) - 1, int(r) + 2):
                if not (l - 0.8 <= x + 0.5 <= r + 0.8):
                    continue
                edge = x + 0.5 - l < (4.5 if self.t else 3.5) or r - x - 0.5 < 3.0
                if y < tip_y + 1 and not edge:
                    continue                                    # las mejillas quedan limpias arriba
                if y < tip_y + 3 and abs(x + 0.5 - (tip - 1)) < 7 and not edge:
                    continue
                if abs(x + 0.5 - mx) < self.mouth_w - 0.5 and my - 1 <= y <= my + 2:
                    continue                                    # la boca
                if y < my - 1 and abs(x + 0.5 - mx) < self.mouth_w + 1 and "mustache" not in self.ex:
                    if y > tip_y + 2:
                        pass
                u = (x + 0.5 - (l + r) / 2) / max(1, (r - l) / 2)
                v = (y + 0.5 - cy) / self.H
                tone = self.lit(u, v + 0.25, 0.7)
                strand = (x * 2 + y) % 4 if u < 0 else (x * 2 - y) % 4
                if strand == 0:
                    tone -= 1
                elif strand == 2 and tone >= 3 and _hash(x, y, self.seed) < 0.5:
                    tone += 1
                if y > self.chin + length - 3 and _hash(x, y, self.seed + 1) < 0.5:
                    continue                                    # las puntas desparejas
                self.put(x, y, mat, max(1, min(4, tone)))
        for x in range(int(mx - 3), int(mx + 2)):              # el labio de abajo asoma
            if self.is_(x, my + 1, "hair", "grey"):
                self.put(x, my + 1, "lip", 3)

    def glasses(self) -> None:
        if not ("pince_nez" in self.f["props"] or "glasses" in self.ex):
            return
        round_ = "glasses" in self.ex
        ey = self.ey
        centers = []
        for cx, w, outer, far in self.eye_pos:
            rx = w / 2 + (1.6 if round_ else 1.0)
            ry = 4.2 if round_ else 3.4
            ccy = ey + self.eye_h / 2 + 0.2
            centers.append((cx, ccy, rx, ry, far))
            for i in range(64):
                a = i / 64 * 2 * math.pi
                x, y = cx + math.cos(a) * rx, ccy + math.sin(a) * ry
                t = 1 if math.sin(a) > -0.3 else 3
                if far:
                    t = 1
                self.put(x, y, "black" if not round_ else "brass", t if not round_ else (2 if t == 1 else 4))
            for k in range(3):                                   # el reflejo del vidrio
                gx, gy = cx - rx * 0.45 + k, ccy - ry * 0.4 + k
                if self.is_(gx, gy, "skin", "eyew", "iris", "lash", "brow"):
                    self.tint(gx, gy, (230, 240, 250), 0.55 - k * 0.12)
                    self.col[(int(gx), int(gy))] = self.col.get((int(gx), int(gy)), (230, 240, 250, 255))
        (ax, ay, arx, _, _), (bx, by, brx, _, _) = sorted(centers)[:2]
        for x in range(int(ax + arx), int(bx - brx) + 1):
            self.put(x, ay - 1.5, "brass" if round_ else "black", 2)
        if self.t:                                               # la patilla hacia la oreja
            cx, ccy, rx, ry, far = centers[0]
            ear_x = self.ear_pos[0][0] if getattr(self, "ear_pos", None) else cx - 10
            self.line([(cx - rx, ccy - 1), (ear_x + 1, ccy - 2)], "brass" if round_ else "black", 2)
        if not round_:                                           # el cordón de los quevedos
            cx, ccy, rx, ry, far = centers[0]
            self.line([(cx - rx, ccy + 1), (cx - rx - 2, ccy + 8), (cx - rx - 1, self.chin + 6)], "black", 2)

    # sombreros ----------------------------------------------------------------
    def hat_layer(self) -> None:
        h = self.hat
        if h in ("rail_cap", "kepi"):
            self.peaked_cap(kepi=h == "kepi")
        elif h == "flat_cap":
            self.flat_cap()
        elif h == "fedora":
            self.fedora()
        elif h == "scarf":
            self.headscarf()
        elif h == "cloche":
            self.cloche()
        elif h == "beret":
            self.beret()

    def visor_shadow(self, y0: int, rows: int) -> None:
        for y in range(y0, y0 + rows):
            for x in range(SIZE):
                if self.is_(x, y, "skin", "hair", "grey", "brow", "stubble"):
                    self.shift(x, y, -2 if y == y0 else -1, "skin", "hair", "grey", "brow", "stubble")
                elif self.is_(x, y, "eyew", "iris"):
                    self.tone[y][x] = max(1, self.tone[y][x] - 1)

    def peaked_cap(self, kepi: bool) -> None:
        hl = int(self.hairline(self.fx)) + (1 if not kepi else 0)
        cx = self.cxh + self.t * 0.8
        hw = self.W + 1.8
        band_bot = hl
        band_top = band_bot - 6
        metal = "gold" if (not kepi or "badge" in self.ex) else "silver"
        if kepi:                                              # quepis: alto, de lados rectos, el plato arriba
            top = self.top - 6
            for y in range(top, band_top + 1):
                q = (y - top) / max(1, band_top - top)
                w = hw - 0.8 + 0.8 * q
                for x in range(int(cx - w - 1), int(cx + w + 2)):
                    if not (cx - w <= x + 0.5 <= cx + w):
                        continue
                    u = (x + 0.5 - cx) / w
                    tone = self.lit(u, 0.0, 0.8)
                    if y <= top + 1:
                        tone = 4 if u < 0.3 else 3                # el plato de arriba
                    self.put(x, y, "hat", tone)
            for x in range(int(cx - hw + 1), int(cx + hw)):
                self.put(x, top + 2, "hat", 1)
        else:                                                 # gorra de plato: la copa más ancha que la cinta
            top = self.top - 3
            for y in range(top, band_top + 1):
                q = (y - top) / max(1, band_top - top)
                w = hw + 3.2 * math.sin(math.pi * min(1.0, q * 0.85 + 0.12))
                for x in range(int(cx - w - 1), int(cx + w + 2)):
                    if not (cx - w <= x + 0.5 <= cx + w):
                        continue
                    u = (x + 0.5 - cx) / w
                    tone = self.lit(u, -0.7 + q * 1.1, 0.7)
                    if q > 0.78:
                        tone = max(1, tone - 1)
                    if y == top:
                        tone = max(tone, 4) if u < 0.4 else tone
                    self.put(x, y, "hat", tone)
            for x in range(int(cx - hw - 3), int(cx + hw + 4)):   # el borde del plato
                if self.is_(x, band_top - 1, "hat"):
                    self.put(x, band_top - 1, "hat", 1)
        for y in range(band_top, band_bot + 1):               # cinta
            for x in range(int(cx - hw), int(cx + hw + 1)):
                u = (x + 0.5 - cx) / hw
                tt = 2 if u < 0.4 else 1
                if y == band_top + 1 and u < 0.3:
                    tt = 3
                self.put(x, y, "hat", tt)
            self.put(cx - hw, y, "hat", 1)
        if kepi:                                              # la franja del quepis
            for x in range(int(cx - hw), int(cx + hw + 1)):
                self.put(x, band_top + 2, metal, 3 if x < cx else 2)
                self.put(x, band_top + 3, "red" if "badge" in self.ex else metal, 2 if x < cx else 1)
        # el barbijo de cordón sobre la visera
        for x in range(int(cx - hw + 1), int(cx + hw)):
            if (x % 3) != 0:
                self.put(x, band_bot - 1, metal if not kepi else "black", 4 if x < cx else 3)
        for side in (-1, 1):
            self.put(cx + side * (hw - 1), band_bot - 1, metal, 5)
        # visera: media luna oscura y brillante, corrida hacia donde mira
        vx = self.fx + self.t * 2.2
        vw = self.W * 0.82 + 2
        for i, y in enumerate(range(band_bot + 1, band_bot + 4)):
            l = vx - vw + i * 2.0
            r = vx + vw - i * 1.6 + (self.t * 1.6 if self.t else 0)
            for x in range(int(l), int(r) + 1):
                if not (l <= x + 0.5 <= r):
                    continue
                tone = 1 if i == 2 else 2
                if i == 0:
                    tone = 3 if x + 0.5 < vx - vw * 0.1 else 2
                self.put(x, y, "black", tone)
            if i == 0:
                for k in range(4):
                    self.put(vx - vw * 0.55 + k, y, "black", 5 if k < 2 else 4)
        self.visor_shadow(band_bot + 4, 3)
        # insignia: la rueda alada del ferrocarril o la granada con la llama
        bx = self.fx + self.t * 0.8
        by = band_top - (3 if not kepi else 6)
        if kepi:
            for dx, dy, t in ((0, 0, 5), (-1, 0, 4), (1, 0, 3), (-1, 1, 3), (0, 1, 4), (1, 1, 2), (0, 2, 2),
                              (0, -1, 4), (1, -2, 4), (0, -3, 3), (1, -4, 2)):
                self.put(bx + dx, by + dy, metal, t)
        else:
            for dx, dy, t in ((0, 0, 5), (-1, 0, 4), (1, 0, 3), (0, -1, 4), (0, 1, 2), (-1, -1, 3), (1, 1, 2),
                              (-2, -1, 4), (-3, -2, 3), (2, -1, 3), (3, -2, 2), (-2, 0, 3), (2, 0, 2)):
                self.put(bx + dx, by + dy, metal, t)

    def flat_cap(self) -> None:
        hl = int(self.hairline(self.fx)) + 1
        cx = self.cxh + self.t * 1.6
        top = self.top - 3
        hw = self.W + 2.4
        for y in range(top, hl + 1):
            q = (y - top) / max(1, hl - top)
            w = hw * (0.74 + 0.3 * math.sqrt(q))
            off = self.t * 3.0 * q
            for x in range(int(cx + off - w - 1), int(cx + off + w + 2)):
                if not (cx + off - w <= x + 0.5 <= cx + off + w):
                    continue
                u = (x + 0.5 - cx - off) / w
                tone = self.lit(u, -0.7 + q * 1.1, 0.7)
                n = _hash(x, y, 11)
                if n < 0.1:
                    tone = max(1, tone - 1)                    # el tweed, moteado
                elif n > 0.96 and tone < 5:
                    tone += 1
                self.put(x, y, "hat", tone)
        for i in range(3):                                      # costuras de los gajos
            sx = cx + (i - 1) * hw * 0.42
            for y in range(top + 1, hl - 1):
                q = (y - top) / max(1, hl - top)
                self.put(sx + (sx - cx) * 0.25 * q + self.t * 3.0 * q, y, "hat", 2)
        self.put(cx - self.t * 0.5, top, "hat", 4)
        self.put(cx - self.t * 0.5 + 1, top, "hat", 3)
        # visera corta, que asoma por delante
        vx = self.fx + self.t * 2.6
        vw = self.W * 0.78
        for i in range(2):
            for x in range(int(vx - vw + i), int(vx + vw + (3 if self.t else 1) - i)):
                self.put(x, hl + 1 + i, "hat", (2 if x + 0.5 < vx else 1) if i == 0 else 1)
        self.put(vx + vw + (2 if self.t else 0), hl + 1, "hat", 0)
        self.visor_shadow(hl + 3, 3)

    def fedora(self) -> None:
        hl = int(self.hairline(self.fx))
        cx = self.cxh + self.t * 0.6
        hw = self.W + 0.4
        top = self.top - 8
        band_bot = hl - 1
        for y in range(top, band_bot + 1):
            q = (y - top) / max(1, band_bot - top)
            w = hw * (0.7 + 0.3 * min(1.0, q * 1.5))
            for x in range(int(cx - w - 1), int(cx + w + 2)):
                if not (cx - w <= x + 0.5 <= cx + w):
                    continue
                u = (x + 0.5 - cx) / w
                tone = self.lit(u, -0.6 + q, 0.75)
                if y <= top + 1 and abs(u) < 0.35:
                    tone = 2                                     # la hendidura de arriba
                if q < 0.55 and abs(abs(u) - 0.55) < 0.08:
                    tone = max(1, tone - 1)                      # los pellizcos de los costados
                self.put(x, y, "hat", tone)
        for y in range(band_bot - 3, band_bot + 1):             # la cinta
            for x in range(int(cx - hw), int(cx + hw + 1)):
                self.put(x, y, "belt", 3 if x < cx - hw * 0.3 else 2 if x < cx + hw * 0.4 else 1)
            self.put(cx - hw * 0.55, y, "belt", 4)
        # ala: elipse ancha, corrida hacia donde mira, que baja adelante
        bxc = cx + self.t * 2.6
        bw = hw + 8
        for i, y in enumerate(range(band_bot + 1, band_bot + 5)):
            ww = bw - (2 if i == 2 else 5 if i == 3 else 0)
            for x in range(int(bxc - ww), int(bxc + ww + 1)):
                rel = (x + 0.5 - bxc) / ww
                tone = 4 if (i == 0 and rel < -0.2) else 3 if i == 0 else 2 if i == 1 else 1
                if i >= 2 and abs(rel) > 0.75:
                    continue
                self.put(x, y, "hat", tone)
            if i == 0:
                self.put(bxc - ww, y - 1, "hat", 3)
                self.put(bxc + ww, y - 1, "hat", 2)
        self.visor_shadow(band_bot + 5, 4)

    def headscarf(self) -> None:
        """Pañuelo atado bajo el mentón: enmarca la cara y tapa el pelo, con pliegues y un estampado chico."""
        cy = self.top + self.H * 0.5
        rx = self.W + 3.6
        ry = self.H * 0.5 + 3.4
        cxs = self.cxh - self.t * 0.8
        fl = int(self.hairline(self.fx)) - 1
        pattern = _lum(self.R["hat"][3]) > 0.3 and self.seed % 2
        for y in range(self.top - 4, self.chin + 4):
            row = self.rows.get(min(max(y, self.top), self.chin))
            for x in range(SIZE):
                dx = (x + 0.5 - cxs) / rx
                dy = (y + 0.5 - cy) / ry
                inside = dx * dx + dy * dy <= 1.0
                if y >= cy and row:                            # abajo, la tela sigue la cara
                    back = 3.6 if self.t else 3.0
                    front = 2.2 if self.t else 3.0
                    inside = row[0] - back <= x + 0.5 <= row[1] + front and y <= self.chin + 2
                if not inside:
                    continue
                face = self.in_head(x, y) and y >= fl and self._face_open(x, y)
                if face:
                    continue
                tone = self.lit(dx, dy, math.sqrt(max(0.05, 1 - dx * dx - dy * dy)))
                ring = math.sqrt(dx * dx + dy * dy)
                if (0.78 < ring < 0.84 or 0.6 < ring < 0.65) and y < cy and _hash(x, y, 4) < 0.8:
                    tone -= 1                                    # pliegues que siguen la cabeza
                if pattern and (x % 4 == 0) and (y % 4 == 0):
                    tone = min(5, tone + 2)                      # lunares del estampado
                self.put(x, y, "hat", max(1, min(5, tone)))
        for y in range(fl, self.chin + 1):                     # borde que enmarca la cara (sombra hacia adentro)
            for x in range(SIZE):
                if self.is_(x, y, "skin") and (self.is_(x - 1, y, "hat") or self.is_(x + 1, y, "hat") or
                                               self.is_(x, y - 1, "hat")):
                    self.shift(x, y, -1, "skin")
        for x in range(SIZE):                                  # el doblez de la tela sobre la frente
            if self.is_(x, fl - 1, "hat") and self.is_(x, fl, "skin"):
                self.put(x, fl - 1, "hat", 4)
                self.put(x, fl - 2, "hat", 2)
        kx = self.mx + self.t * 0.5
        ky = self.chin + 3
        for dx, dy, t in ((-2, 0, 3), (-1, 0, 4), (0, 0, 4), (1, 0, 3), (2, 0, 2), (-1, 1, 2), (0, 1, 3), (1, 1, 2),
                          (0, 2, 1), (-3, 2, 3), (-4, 3, 3), (-5, 4, 2), (-4, 5, 2), (2, 2, 2), (3, 3, 2), (4, 4, 1),
                          (4, 5, 1)):
            self.put(kx + dx, ky + dy, "hat", t)

    def _face_open(self, x: int, y: int) -> bool:
        l, r = self.rows[y]
        inset = 1.6 + (0.8 if y < self.ey - 4 else 0)
        il = inset + (3.0 if self.t else 0)
        ir = inset - (0.6 if self.t else 0)
        if self.t and y > self.ey - 4:
            il = min(il, 5.5)
        return l + il <= x + 0.5 <= r - ir and y <= self.chin

    def cloche(self) -> None:
        cx = self.cxh - self.t * 0.4
        hw = self.W + 2.6
        top = self.top - 3
        bot = int(self.ey - self.brow_h - 2)
        for y in range(top, bot + 1):
            q = (y - top) / max(1, bot - top)
            w = hw * math.sqrt(max(0.0, 1 - (1 - min(1.0, q * 1.6)) ** 2)) + 0.8
            for x in range(int(cx - w - 1), int(cx + w + 2)):
                if not (cx - w <= x + 0.5 <= cx + w):
                    continue
                u = (x + 0.5 - cx) / w
                self.put(x, y, "hat", self.lit(u, -0.7 + q, 0.7))
        for y in range(bot - 4, bot - 1):                       # la cinta y el moño
            for x in range(int(cx - hw), int(cx + hw + 1)):
                self.put(x, y, "black", 2 if x < cx + 5 else 1)
        bx = cx - hw * 0.55
        for dx, dy, t in ((0, 0, 4), (-1, -1, 3), (1, -1, 3), (-2, -2, 2), (2, -2, 2), (-1, 1, 2), (1, 1, 2),
                          (0, -1, 5)):
            self.put(bx + dx, bot - 3 + dy, "black", t)
        bw = hw + 2
        for x in range(int(cx - bw + self.t), int(cx + bw + self.t + 1)):
            self.put(x, bot, "hat", 3 if x < cx else 2)
            self.put(x, bot + 1, "hat", 2 if x < cx else 1)
            if abs(x + 0.5 - cx - self.t) < bw - 3:
                self.put(x, bot + 2, "hat", 1)
        self.visor_shadow(bot + 3, 3)

    def beret(self) -> None:
        cx = self.cxh - self.t * 1.6 - 1
        cy = self.top + 1
        rx = self.W + 5
        ry = 6.5
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                dx = (x + 0.5 - cx) / rx
                dy = (y + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1:
                    tone = self.lit(dx, dy - 0.3, 0.7)
                    if dy > 0.55:
                        tone = max(1, tone - 1)
                    if _hash(x, y, 13) < 0.15:
                        tone = max(1, tone - 1)                # el fieltro
                    self.put(x, y, "hat", tone)
        for x in range(int(cx - rx + 2), int(cx + rx - 1)):     # el ribete de abajo
            yy = cy + ry * math.sqrt(max(0, 1 - ((x + 0.5 - cx) / rx) ** 2)) - 1
            self.put(x, yy, "hat", 1)
        self.put(cx + 1, cy - ry - 1, "hat", 2)
        self.put(cx + 1, cy - ry - 2, "hat", 1)
        self.put(cx + 2, cy - ry - 2, "hat", 2)

    # objetos ---------------------------------------------------------------------
    def props(self) -> None:
        props = self.f["props"]
        if "scarf" in props:
            nb = self.neck_half()
            y0 = self.body_top - 6
            for y in range(y0, y0 + 9):
                w = nb + 4 + (y - y0) * 0.35
                for x in range(int(self.neck_x - w), int(self.neck_x + w + 1)):
                    u = (x + 0.5 - self.neck_x) / w
                    tone = 4 if u < -0.4 else 3 if u < 0.4 else 2
                    if ((x + (y // 2)) % 4 == 0) ^ ((x - (y // 2)) % 4 == 0):
                        tone -= 1                                # el tejido
                    if y in (y0 + 3, y0 + 6) and u > -0.8:
                        tone -= 1                                # las vueltas
                    if y == y0 + 8:
                        tone = 1
                    self.put(x, y, "scarf", tone)
            ex = self.bx - 5 if self.t else self.bx + 3
            for y in range(y0 + 8, y0 + 24):
                for i in range(5):
                    self.put(ex + i + (y - y0) * 0.12, y, "scarf", (4, 4, 3, 3, 2)[i] - (1 if y % 4 == 0 else 0))
                self.put(ex + 5 + (y - y0) * 0.12, y, "scarf", 1)
            for i in range(5):                                   # flecos
                if i % 2 == 0:
                    self.put(ex + i + 24 * 0.12, y0 + 24, "scarf", 2)
        if "pearl_necklace" in props:
            for i in range(-7, 8):
                x = self.neck_x + i
                y = self.body_top + 1 + int(abs(i) < 5) + int(abs(i) < 3)
                if i % 2 == 0:
                    self.put(x, y, "pearl", 5 if i < 0 else 4)
        if "rosary" in props:
            y0 = self.body_top + 4
            for i in range(14):
                x = self.bx - 6 + i * 0.35
                y = y0 + i * 1.4
                if i % 2 == 0:
                    self.put(x, y, "brass" if self.d["garment"] != "cassock" else "white", 4)
                    self.put(x + 1, y, "brass" if self.d["garment"] != "cassock" else "white", 2)
            cx, cy = self.bx - 6 + 5, y0 + 20
            for dx, dy, t in ((0, 0, 4), (0, 1, 4), (0, 2, 3), (0, 3, 3), (0, 4, 2), (-1, 1, 4), (1, 1, 3),
                              (-2, 1, 3), (2, 1, 2)):
                self.put(cx + dx, cy + dy, "silver", t)
        if "medal" in props:
            mx, my = self.bx - 12, self.body_top + 13
            for dy, mat, t in ((0, "tie", 3), (1, "tie", 2), (2, "white", 4), (3, "tie", 2)):
                for dx in range(3):
                    self.put(mx + dx, my + dy, mat, t - (1 if dx == 2 else 0))
            for dx, dy, t in ((0, 4, 4), (1, 4, 5), (2, 4, 3), (0, 5, 3), (1, 5, 4), (2, 5, 2), (1, 6, 2)):
                self.put(mx + dx, my + dy, "gold", t)
        if "pencil_ear" in props:
            ex = self.ear_pos[0][0] if getattr(self, "ear_pos", None) else self.rows[self.ey][0]
            for i in range(9):
                x = ex + 4 - i * 0.95
                y = self.ey - 5 + i * 0.3
                mat, t = ("brass", 4) if i < 7 else ("paper", 3) if i < 8 else ("black", 1)
                self.put(x, y, mat, t)
                self.put(x, y + 1, mat, t - 2 if mat == "brass" else t - 1)
        if "cigarette" in props:
            x1 = self.mouth_x[1] if self.t else self.mouth_x[1]
            x0 = x1 - 1
            for i in range(7):
                self.put(x0 + i, self.my + i * 0.3, "paper", 5 if i < 6 else 3)
                self.put(x0 + i, self.my + 1 + i * 0.3, "paper", 2)
            tip_x = x0 + 7
            self.put(tip_x, self.my + 2, "ember", 5)
            self.put(tip_x, self.my + 3, "ember", 3)
            for i, (dx, dy) in enumerate(((1, -1), (0, -3), (1, -5), (2, -7), (1, -9), (2, -11))):
                x, y = tip_x + dx, self.my + dy
                if 0 <= int(x) < SIZE and 0 <= int(y) < SIZE:
                    base = self.col.get((int(x), int(y))) or (self.R[self.mat[int(y)][int(x)]][self.tone[int(y)][int(x)]]
                                                              if self.mat[int(y)][int(x)] else hexc(self.d.get("bg", "#4A4A50")))
                    self.mat[int(y)][int(x)] = self.mat[int(y)][int(x)] or "smoke"
                    self.col[(int(x), int(y))] = _mix(base, (210, 210, 214), 0.45 - i * 0.06)
        if "pipe" in props:
            x0 = self.mouth_x[1] - 1
            for i in range(7):
                self.put(x0 + i, self.my + 1 + i * 0.45, "pipe", 1 if i < 3 else 2)
                self.put(x0 + i, self.my + i * 0.45, "black", 2)
            bx = x0 + 7
            for dy in range(0, 6):
                for dx in range(0, 4):
                    t = (4, 3, 3, 2)[dx] if dy else 1
                    if dy == 5 and dx in (0, 3):
                        continue
                    self.put(bx + dx - 1, self.my - 1 + dy, "pipe", t)
            self.put(bx, self.my - 1, "ember", 4)

    # salida ---------------------------------------------------------------------------
    def image(self) -> Image.Image:
        bg = hexc(self.d.get("bg", "#4A4A50"))
        self.R["smoke"] = [bg] * 6
        img = Image.new("RGBA", (SIZE, SIZE), bg)
        px = img.load()
        for y in range(SIZE):
            for x in range(SIZE):
                m = self.mat[y][x]
                if m:
                    px[x, y] = self.col.get((x, y)) or self.R[m][self.tone[y][x]]
        out = img.copy()
        po = out.load()
        for y in range(SIZE):                                  # contorno del tono más oscuro del vecino
            for x in range(SIZE):
                if self.mat[y][x] and self.mat[y][x] != "smoke":
                    continue
                for dx, dy in ((0, 1), (1, 0), (-1, 0), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < SIZE and 0 <= ny < SIZE and self.mat[ny][nx] and self.mat[ny][nx] != "smoke":
                        c = _mix(self.R[self.mat[ny][nx]][0], (20, 14, 16, 255), 0.45)   # contorno oscuro y firme
                        po[x, y] = _mix(c, bg, 0.15) if dx > 0 else c
                        break
        if self.mirror:
            out = out.transpose(Image.FLIP_LEFT_RIGHT)
            po = out.load()
        for i in range(SIZE):                                  # marco
            for c in ((i, 0), (i, SIZE - 1), (0, i), (SIZE - 1, i)):
                po[c] = FRAME
        return out


def portrait(d: dict, seed: str) -> Image.Image:
    """Busto de 96x96 sobre el color `bg`; `seed` (el id del personaje) fija lo que no dice la descripción."""
    return Bust(d, seed).render()
