# Horarios de los NPCs

Generado por `addons/jornada/tools/schedule_table.py` desde `data/schedules/*.json`: **no se edita a mano**.
Al cambiar un horario, volver a correrlo (`tools/run_tests.sh` falla si la tabla quedó vieja).
Las horas son de llegada; el personaje sale antes, según el camino. «gone» = fuera del mapa.

## Dónde está cada uno

| Personaje | 07:00 | 07:30 | 08:00 | 08:30 | 09:00 | 09:30 | 10:00 | 10:30 | 11:00 | 11:30 | 12:00 | 12:30 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Lucía | gone | · | · | plaza | · | · | · | · | · | · | · | gone |
| Marta Ruiz | panaderia | · | · | · | · | · | · | plaza | · | panaderia | · | · |
| Tomás Prieto | gone | · | · | · | plaza | · | panaderia | plaza | · | · | gone | · |

«·» = sigue donde estaba.

## Cuánta gente hay en cada lugar

| Lugar | 07:00 | 07:30 | 08:00 | 08:30 | 09:00 | 09:30 | 10:00 | 10:30 | 11:00 | 11:30 | 12:00 | 12:30 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| panaderia | 1 | 1 | 1 | 1 | 1 | 1 | 2 |  |  | 1 | 1 | 1 |
| plaza |  |  |  | 1 | 2 | 2 | 1 | 3 | 3 | 2 | 1 |  |

## El día de cada uno

- **Lucía** (`lucia`): 07:00 gone → 08:30 plaza [26, 17] → 11:00 plaza [10, 21] (mon, wed) → 12:30 gone
- **Marta Ruiz** (`marta`): 07:00 panaderia [3, 5] → 10:30 plaza [24, 13] → 11:15 panaderia [3, 5]
- **Tomás Prieto** (`tomas`): 07:00 gone → 09:00 plaza [6, 14] → 09:40 panaderia [5, 8] → 10:10 plaza [36, 14] → 12:00 gone
