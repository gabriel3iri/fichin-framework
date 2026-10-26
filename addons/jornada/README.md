# jornada

Framework para Godot 4 (GDScript tipado) de juegos 2D top-down armados alrededor de **un día**: un reloj que corre,
gente que sigue su horario, conversaciones con condiciones, un diario que recuerda lo que se supo, y lo que pasa
cuando la jornada termina. El fin de la jornada es un **modo**:

- **loop**: vuelve a empezar el mismo día; se recuerda lo aprendido y el mundo se reinicia.
- **next_day**: pasa al día siguiente y el calendario avanza (una semana en un colegio, turnos en un restaurante).

Todo lo que es de un juego en particular (historia, personajes, mapas, textos y arte) está en los datos del juego. El
framework no nombra nada de ningún juego. Un ejemplo completo y chico está en `examples/primer_dia/`: dos zonas, tres
vecinos y tres días en una panadería.

## Instalar

1. Copiar (o enlazar) `addons/jornada/` al proyecto.
2. Autoloads en `project.godot`, **en este orden**, más los del juego al final:
   `GameConfig` (core/game_config.gd, siempre el primero), `TimeManager`, `SettingsManager`, `LoopManager`,
   `JournalManager`, `DeductionSystem`, `Toasts`, `GameManager`, `DialogueManager`, `ZoneManager`, `TimedEvents`,
   `WorkManager`, `AudioManager`, `SaveManager`, `WorldEffects`, `WitnessManager`, `AnnoyanceSystem`, `PrivateRooms`,
   `ChatterSystem`, `Identification`, `Sightings`, `SearchSystem` (rutas en `core/`, `social/`, `world/` y `work/`; el `project.godot` del ejemplo sirve de plantilla).
3. Traducciones: `addons/jornada/translations/jornada.es.translation` (textos de la UI del framework) y las del
   juego. Tema: `addons/jornada/ui/skin/theme.tres`.
4. Acciones de entrada: `move_left`, `move_right`, `move_up`, `move_down`, `run`, `interact`, `pause_menu`,
   `quick_save`, `quick_load`, `journal`, `work_order`.
5. Resolución base 640×360 (`canvas_items`), GL Compatibility.

## Qué pone el juego

| Qué | Dónde | Para qué |
|---|---|---|
| Reglas | `data/game.json` | escenas, inicio, jornada (`day`), roles de flags, intro, pensamientos, sospecha, trabajo, gente |
| Lo que se puede saber | clase `KnowledgeRegistry` (`class_name`) | enum `Kind` (`WITNESS`, `TESTIMONY`, `DOCUMENT`, `PHYSICAL`, `HEARD`, `TRUST`, `DEDUCTION`, `STATE`, `NEGATIVE`), `FLAGS`, `is_valid(flag)`, `kind_of(flag)`; un flag que no esté no existe. `HEARD` (OÍDO) es obligatorio aunque el juego no lo use: el diario y los toasts del framework lo nombran |
| Mundo | `data/world.json`, `data/zones.json`, `data/layouts/*.json` | tiles, estilos, objetos, zonas y su contenido (ver "Mundo") |
| Gente | `data/schedules/<id>.json`, `data/dialogue/<id>.json` | horarios (hora de llegada, zona, celda) y conversaciones |
| Diario | `data/journal.json` | fichas de las personas, grupos, deducciones, mapa |
| Escenas | jugador, menú y partida (`scenes` en game.json) | finas: scripts del framework con el arte del juego |
| Textos | `assets/translations/game.csv` | todo lo visible es una clave `tr()` |
| Arte | `assets/generated_assets/` | tiles, objetos, hojas de personajes, retratos (ver "Arte") |

Mecánicas opcionales: si el archivo no existe, el juego no la usa y no hay error. `data/events.json` (eventos a hora
fija), `work.json` (orden de trabajo y minijuegos), `audio.json`, `lighting.json`, `weather.json`, `witness.json`
(lo que se anota por ver a alguien), `locks.json` (puertas con llave), `private_rooms.json`, `annoyance.json`,
`barks.json` (frases sueltas y charlas), `search.json` (alguien busca al jugador si va atrasado con el trabajo: llega solo adonde lo vio un testigo, ver `social/search_system.gd`), `inspectables.json` (objetos examinables), `buildings.json` (edificios
dibujados enteros).

### Claves de texto que pone cada juego

Las de la UI genérica vienen en `translations/jornada.csv` y el juego no las repite. El juego pone:

- **Por persona** `<id>`: `who_<id>` (cómo se lo describe sin conocerlo), `first_<id>`, `last_<id>`, `chr_<id>`
  (nombre completo), `role_<id>`, `bio_<id>`.
- **Por flag**: `flag_<flag>` (título) y `desc_<flag>` (detalle); las deducciones, su `title_key`.
- **Por zona**: `zone_<id>`.
- **Menú**: `ui_menu_subtitle`, `ui_menu_place`, `ui_menu_version` y `ui_menu_continue_tip` (`%d` jornada, `%s` cuándo se guardó).
- **Diario y trabajo**: `toast_journal_hint`, `ui_journal_seal_hint`, `work_panel_title`, `work_pay`,
  `toast_work_failed` y `toast_work_late`.
- Las que nombre `game.json` (`intro`, `thoughts`) y los datos (diálogos, eventos, frases).

`DataValidator` (corre al cargar la partida en debug) revisa claves, flags, horarios, diálogos y celdas.

## Puntos de extensión

- `WorldEffects.register(id, func)`: efectos que disparan diálogos y objetos (`"effects": ["id"]`).
- `LoopManager.end_of_day_handler` y `LoopManager.end_day(motivo)`: qué pasa al terminar la jornada (por defecto,
  la siguiente). Señales `loop_started`, `knowledge_gained`, `game_reset`.
- `SaveManager.register_section(clave, guardar, cargar)`: lo que el juego guarda en la partida.
- `TimedEvents.register_sound_source(nombre, func)`: de dónde sale un sonido de `events.json` (`"source"`).
- Horarios: `"stay_if"`, `"days"` y `"weekdays"`; eventos: `"days"` y `"weekdays"`.
- Diario: pestaña `"roster"` en `journal.json` (una lista que se desbloquea con un flag).
- Horarios: `python3 addons/jornada/tools/schedule_table.py [--root <proyecto>] [--check]` escribe la tabla
  `docs/HORARIOS.md` desde `data/schedules/*.json` y revisa orden, zonas y choques de celda. Para traer a un NPC hasta
  el jugador sin que aparezca de golpe: `NpcActor.approach_player()` (y `end_detour()` al terminar).
- Identificar gente (`data/identify.json`, `Identification`): fichas con cara y descripción, nombres que desbloquean
  flags, confirmación de a `batch` aciertos sin decir cuál está mal (al estilo Obra Dinn); pestaña propia en el diario.
- Minijuegos de trabajo: extender `Minigame` (`work/minigame.gd`) y nombrar el script en `work.json`.

## Mundo

`godot --headless --path . res://addons/jornada/tools/build_world.tscn` arma el TileSet, una escena por zona y la
escena de la partida a partir de los datos (repetir con `--import` en el medio si cambian los PNG de tiles).

- `data/world.json`: lista de tiles (orden = columna del atlas; `solid`, `window`, `sun`), piezas de puertas,
  estilos de pared y techo, el seto del borde de los exteriores, bordes entre suelos, objetos con su base de colisión,
  rutas y la lista de personajes.
- `data/zones.json`: cada zona con su escena, tamaño, layout y conexiones (puertas con `door_tile`, o bordes con
  `kind: "edge"`). Una zona es interior si su layout lo es (o `"exterior": false`).
- Layouts: `grid` (filas de caracteres + `legend`), `interior` (cuarto con pared norte, ventanas, puertas a cuartos
  hijos, mostradores y salida al sur) u `outdoor` (suelo, rectángulos `fills`, edificios y seto). Todos aceptan
  `props`, `spots` (puestos de trabajo) y `nodes` (nodos con script del juego).

## Cámara y nombres

- `world/player_camera.gd`: la cámara va pegada al jugador en cada cuadro dibujado (sin suavizado ni interpolación de
  física; el jugador tampoco se interpola), hace su propio límite contra los bordes del mapa (centra las zonas más
  chicas que la pantalla) y redondea su posición para que el mundo se dibuje siempre desde un píxel entero. Con
  zooms no enteros (1,5) es lo que evita que todo tiemble un píxel. Zooms en `PlayerCamera.ZOOMS` (tecla Z).
- Los nombres sobre la cabeza de cada personaje salen solo al pasar el mouse, en un recuadro negro con borde marrón
  (`UiStyle.name_tag()`), distinto de los diálogos. La N los muestra todos mientras dura la sesión (depuración).

## Arte

`tools/pixel/` es una librería de Python (Pillow) para dibujar con la misma paleta y formato:

- `pixel.core`: paleta, `Canvas` (formas + contorno), `noise`, `save_sheet` (la hoja de personaje que lee
  `world/character_frames.gd`).
- `pixel.figures`: personajes y retratos **por descripción** (`build_frames(desc)`, `portrait(desc, seed)`); el
  vocabulario está al principio del archivo.
- `pixel.skin`: la piel por defecto de la UI (`python3 addons/jornada/tools/pixel/skin.py`).

Rutas que usa el framework: `assets/generated_assets/sprites/protagonist_sheet.png`,
`.../sprites/npcs/<id>_sheet.png`, `.../portraits/<id>.png`; tiles, objetos y edificios donde diga `world.json`.

## Pruebas

`testkit/runner.gd` corre cada `test_*` de `res://tests/test_*.gd` (`test_slow_*` solo con `--slow`) y antes revisa
que todo compile. `testkit/test_case.gd` trae asserts y esperas (`frames`, `seconds`, `until`, `press`);
`testkit/game_case.gd` suma `start_game`, `set_clock`, `go`, `speed_up` y `reachable`.

```bash
godot --headless --path . -s res://addons/jornada/testkit/runner.gd -- [--slow] [filtro]
```

## Juego de ejemplo

`examples/primer_dia/` es un proyecto aparte que usa este mismo addon (enlace simbólico): `tools/make_art.py` dibuja
el arte con `pixel`, los datos están a mano y `run_tests.sh` corre sus pruebas. Si el ejemplo anda sin tocar el
addon, el framework sirve para algo más que el juego para el que nació.
