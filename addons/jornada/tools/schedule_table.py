#!/usr/bin/env python3
"""Tabla de horarios de los NPCs, generada desde data/schedules/*.json (la única fuente de verdad).

Escribe un Markdown con: el día de cada personaje (adónde llega y a qué hora), una grilla de dónde está cada uno cada
media hora y cuánta gente hay en cada lugar. Además revisa los horarios:
  - las horas de cada personaje van en orden y dentro de la jornada (data/game.json, "day");
  - cada zona existe (data/zones.json) y cada punto que no es "gone" tiene celda;
  - dos personas no tienen la misma celda de la misma zona al mismo tiempo;
  - "face" (hacia dónde mira al llegar) es up, down, left o right.

    python3 addons/jornada/tools/schedule_table.py                 # escribe docs/HORARIOS.md
    python3 addons/jornada/tools/schedule_table.py --check         # falla si la tabla no está al día o hay errores
    python3 addons/jornada/tools/schedule_table.py --root examples/primer_dia --out docs/HORARIOS.md

Las horas son de LLEGADA (así las lee npc_actor.gd): el personaje sale antes, según el largo del camino. Un punto con
"days" o "weekdays" vale solo esos días; la tabla lo marca y no lo cuenta para los choques.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

GONE = "gone"
STEP = 30   # minutos entre columnas de la grilla


def clock(text: str) -> int:
    h, m = text.split(":")
    return int(h) * 60 + int(m)


def hhmm(minutes: int) -> str:
    return "%02d:%02d" % (minutes // 60, minutes % 60)


def load_names(root: Path) -> dict[str, str]:
    """Nombre visible de cada personaje (clave chr_<id> en cualquier CSV de traducciones del proyecto)."""
    names: dict[str, str] = {}
    for path in sorted(root.rglob("*.csv")):
        if ".godot" in path.parts:
            continue
        with open(path, encoding="utf-8") as f:
            for row in csv.reader(f):
                if len(row) > 1 and row[0].startswith("chr_") and row[1]:
                    names.setdefault(row[0][4:], row[1])
    return names


def load(root: Path) -> tuple[dict, dict[str, list[dict]], set[str]]:
    game = json.loads((root / "data" / "game.json").read_text(encoding="utf-8")) if (root / "data" / "game.json").exists() else {}
    zones_path = root / "data" / "zones.json"
    zones = set(json.loads(zones_path.read_text(encoding="utf-8")).get("zones", {})) if zones_path.exists() else set()
    schedules: dict[str, list[dict]] = {}
    for path in sorted((root / "data" / "schedules").glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        schedules[data.get("npc_id", path.stem)] = data.get("entries", [])
    return game, schedules, zones


def check(game: dict, schedules: dict[str, list[dict]], zones: set[str]) -> list[str]:
    errors: list[str] = []
    day = game.get("day", {})
    start, end = clock(day.get("start", "00:00")), clock(day.get("end", "23:59"))
    for npc, entries in schedules.items():
        last = -1
        for e in entries:
            t = clock(e["time"])
            if t <= last:
                errors.append(f"{npc}: {e['time']} no va después de la anterior")
            if not start <= t <= end:
                errors.append(f"{npc}: {e['time']} queda fuera de la jornada ({hhmm(start)}-{hhmm(end)})")
            last = t
            if e["zone"] != GONE and zones and e["zone"] not in zones:
                errors.append(f"{npc}: {e['time']} va a una zona que no existe ({e['zone']})")
            if e["zone"] != GONE and "tile" not in e:
                errors.append(f"{npc}: {e['time']} no dice en qué celda de {e['zone']}")
            if e.get("face", "down") not in ("up", "down", "left", "right"):
                errors.append(f"{npc}: {e['time']} mira hacia «{e['face']}» (up, down, left o right)")
    # Choques: misma zona y celda, con estadías que se pisan (de la llegada a la llegada siguiente).
    stays: list[tuple[str, str, tuple[int, int], int, int]] = []
    for npc, entries in schedules.items():
        for i, e in enumerate(entries):
            if e["zone"] == GONE or "tile" not in e or "days" in e or "weekdays" in e:
                continue
            until = clock(entries[i + 1]["time"]) if i + 1 < len(entries) else end
            stays.append((npc, e["zone"], tuple(e["tile"]), clock(e["time"]), until))
    for i, a in enumerate(stays):
        for b in stays[i + 1:]:
            if a[0] != b[0] and a[1] == b[1] and a[2] == b[2] and a[3] < b[4] and b[3] < a[4]:
                errors.append(f"{a[0]} y {b[0]}: los dos en {a[1]} {list(a[2])} entre {hhmm(max(a[3], b[3]))} y {hhmm(min(a[4], b[4]))}")
    return errors


def where(entries: list[dict], minutes: int) -> str:
    here = ""
    for e in entries:
        if clock(e["time"]) <= minutes and "days" not in e and "weekdays" not in e:
            here = e["zone"]
    return here


def render(game: dict, schedules: dict[str, list[dict]], names: dict[str, str]) -> str:
    day = game.get("day", {})
    start, end = clock(day.get("start", "06:00")), clock(day.get("end", "18:00"))
    columns = list(range(start - start % STEP, end, STEP))
    label = lambda npc: names.get(npc, npc)
    order = sorted(schedules, key=lambda n: (n.startswith("x_"), label(n).lower()))
    out = ["# Horarios de los NPCs", "",
           "Generado por `addons/jornada/tools/schedule_table.py` desde `data/schedules/*.json`: **no se edita a mano**.",
           "Al cambiar un horario, volver a correrlo (`tools/run_tests.sh` falla si la tabla quedó vieja).",
           "Las horas son de llegada; el personaje sale antes, según el camino. «gone» = fuera del mapa.", ""]
    out += ["## Dónde está cada uno", "", "| Personaje | " + " | ".join(hhmm(c) for c in columns) + " |",
            "|---|" + "---|" * len(columns)]
    for npc in order:
        cells = []
        prev = None
        for c in columns:
            z = where(schedules[npc], c)
            cells.append("·" if z == prev else (z or "—"))   # «·» = sigue en el mismo lugar
            prev = z
        out.append(f"| {label(npc)} | " + " | ".join(cells) + " |")
    out += ["", "«·» = sigue donde estaba.", "", "## Cuánta gente hay en cada lugar", ""]
    zones = sorted({e["zone"] for es in schedules.values() for e in es if e["zone"] != GONE})
    out += ["| Lugar | " + " | ".join(hhmm(c) for c in columns) + " |", "|---|" + "---|" * len(columns)]
    for z in zones:
        counts = [sum(1 for es in schedules.values() if where(es, c) == z) for c in columns]
        out.append(f"| {z} | " + " | ".join(str(n) if n else "" for n in counts) + " |")
    out += ["", "## El día de cada uno", ""]
    for npc in order:
        steps = []
        for e in schedules[npc]:
            tile = " %s" % list(e["tile"]) if "tile" in e and e["zone"] != GONE else ""
            when = ""
            if "days" in e:
                when = " (días %s)" % ", ".join(str(d) for d in e["days"])
            if "weekdays" in e:
                when = " (%s)" % ", ".join(e["weekdays"])
            steps.append(f"{e['time']} {e['zone']}{tile}{when}")
        out.append(f"- **{label(npc)}** (`{npc}`): " + " → ".join(steps))
    return "\n".join(out) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", default=".", help="raíz del proyecto (donde está data/)")
    parser.add_argument("--out", default="docs/HORARIOS.md", help="Markdown a escribir, relativo a --root")
    parser.add_argument("--check", action="store_true", help="no escribe: falla si hay errores o la tabla está vieja")
    args = parser.parse_args()
    root = Path(args.root)
    game, schedules, zones = load(root)
    errors = check(game, schedules, zones)
    for e in errors:
        print("horarios:", e)
    text = render(game, schedules, load_names(root))
    out = root / args.out
    if args.check:
        stale = not out.exists() or out.read_text(encoding="utf-8") != text
        if stale:
            print(f"horarios: {args.out} no está al día (correr addons/jornada/tools/schedule_table.py)")
        return 1 if errors or stale else 0
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8")
    print(f"{args.out}: {len(schedules)} personajes" + (f", {len(errors)} errores" if errors else ""))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
