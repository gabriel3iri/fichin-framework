# jornada

Framework para Godot 4 (GDScript tipado, GL Compatibility, 640×360) de juegos 2D top-down armados alrededor de **un
día**: un reloj que corre, gente que sigue su horario, conversaciones con condiciones, un diario que recuerda lo que se
supo, y lo que pasa cuando la jornada termina. El fin de la jornada es un **modo**:

- **loop**: vuelve a empezar el mismo día; se recuerda lo aprendido y el mundo se reinicia.
- **next_day**: pasa al día siguiente y el calendario avanza (una semana en un colegio, turnos en un restaurante).

Todo lo que es de un juego en particular (historia, personajes, mapas, textos y arte) está en los datos del juego. El
framework no nombra nada de ningún juego. Un ejemplo completo y chico está en `examples/primer_dia/`: dos zonas, tres
vecinos y tres días en una panadería (más una jornada especial, la feria).

Índice: [Instalar](#instalar) · [Qué pone el juego](#qué-pone-el-juego) · [`game.json`](#datagamejson) ·
[El reloj](#el-reloj-y-el-día-de-la-marmota) · [Jornadas especiales](#jornadas-especiales) · [Gente](#gente-horarios) ·
[Diálogos](#diálogos) · [Barullo y llamados](#barullo-y-llamados) · [Sistemas sociales](#otros-sistemas-de-la-gente) ·
[Diario](#el-diario) · [Trabajo](#trabajo-energía-y-dinero) · [Extensión](#puntos-de-extensión) · [Mundo](#mundo) ·
[Arte](#arte) · [Validación](#validación) · [Pruebas](#pruebas)

## Instalar

1. Copiar (o enlazar) `addons/jornada/` al proyecto.
2. Autoloads en `project.godot`, **en este orden**, más los del juego al final (el `project.godot` del ejemplo sirve de
   plantilla):

   | Autoload | Script | |
   |---|---|---|
   | `GameConfig` | `core/game_config.gd` | siempre el primero: lee `data/game.json` |
   | `TimeManager`, `SettingsManager`, `LoopManager` | `core/` | reloj, opciones, jornadas y flags |
   | `JournalManager`, `DeductionSystem` | `social/` | diario y deducciones |
   | `Toasts`, `GameManager` | `core/` | avisos, arranque, pausa y sospecha |
   | `DialogueManager`, `ZoneManager`, `TimedEvents` | `social/`, `world/`, `core/` | charlas, zonas, eventos |
   | `WorkManager`, `AudioManager`, `SaveManager` | `work/`, `core/` | trabajo, sonido, guardado |
   | `Trust`, `Cases` | `social/` | confianza y tablero de casos |
   | `WorldEffects`, `WitnessManager`, `AnnoyanceSystem` | `social/` | efectos, testigos, fastidio |
   | `PrivateRooms`, `ChatterSystem`, `Identification` | `world/`, `social/` | cuartos ajenos, barullo, fichas |
   | `Sightings`, `SearchSystem`, `Notices`, `EscortSystem` | `social/`, `core/` | avistamientos, búsqueda, carteles, escolta |
   | `Stamina`, `Speeches`, `Wallet` | `core/`, `social/` | energía, discursos y asientos, dinero |
   | `IdleThoughts` | `social/idle_thoughts.gd` | opcional: pensar quieto (sin `idle_thoughts` en game.json no hace nada) |

   Todos (salvo `IdleThoughts`) son obligatorios aunque el juego no use la mecánica: el resto del framework los nombra.
   Sin su archivo de datos, cada uno queda apagado. `Daily` (`core/daily.gd`) **no** es un autoload: quien lo usa lo
   precarga (`const Daily := preload("res://addons/jornada/core/daily.gd")`).
3. Traducciones: `addons/jornada/translations/jornada.es.translation` (textos de la UI del framework) y las del
   juego. Tema: `addons/jornada/ui/skin/theme.tres`.
4. Acciones de entrada: `move_left`, `move_right`, `move_up`, `move_down`, `run`, `interact`, `pause_menu`,
   `quick_save`, `quick_load`, `journal`, `work_order`.
5. Resolución base 640×360 (`canvas_items`), GL Compatibility.

## Qué pone el juego

| Qué | Dónde | Para qué |
|---|---|---|
| Reglas | `data/game.json` | escenas, inicio, jornada, roles de flags, intro, pensamientos, sospecha, gente, diario, jornadas especiales (ver abajo) |
| Lo que se puede saber | clase `KnowledgeRegistry` (`class_name`) | enum `Kind` (`WITNESS`, `TESTIMONY`, `DOCUMENT`, `PHYSICAL`, `HEARD`, `TRUST`, `DEDUCTION`, `STATE`, `NEGATIVE`), `FLAGS`, `is_valid(flag)`, `kind_of(flag)`; un flag que no esté no existe (en debug, `gain_knowledge` de uno desconocido es un error). `HEARD` (OÍDO) es obligatorio aunque el juego no lo use: el diario y los avisos del framework lo nombran |
| Mundo | `data/world.json`, `data/zones.json`, `data/layouts/*.json` | tiles, estilos, objetos, zonas y su contenido (ver [Mundo](#mundo)) |
| Gente | `data/schedules/<id>.json`, `data/dialogue/<id>.json` | horarios y conversaciones |
| Diario | `data/journal.json` | fichas de las personas, grupos, deducciones, lista, preguntas, mapa |
| Escenas | jugador, menú y partida (`scenes` en game.json) | finas: scripts del framework con el arte del juego |
| Textos | `assets/translations/game.csv` | todo lo visible es una clave `tr()` |
| Arte | `assets/generated_assets/` | tiles, objetos, hojas de personajes, retratos (ver [Arte](#arte)) |

**Mecánicas opcionales**: si el archivo no existe, el juego no la usa y no hay error (`GameConfig.read_data`).

| Archivo | Sistema | Qué hace |
|---|---|---|
| `events.json` | `TimedEvents` | eventos a hora fija (sonido, flags), con `days`/`weekdays` y `source` (sonido que se oye según la distancia) |
| `work.json` | `WorkManager` | la orden de trabajo, sus tareas y minijuegos ([Trabajo](#trabajo-energía-y-dinero)) |
| `audio.json` | `AudioManager` | música por hora, ambiente por zona, cambios de ambiente, gentío, persecución, pasos por suelo |
| `lighting.json` | `DayLight` | color del día por hora, sol por las ventanas, halos, interiores oscuros (`dim`) |
| `weather.json` | `Weather` | niebla, lluvia, nieve y viento por hora, niebla propia de cada zona |
| `witness.json` | `WitnessManager` | lo que se anota por ver a alguien en un lugar y a una hora |
| `locks.json` | `DoorLocks` | puertas con llave: `open_from`, `open_if_any`, `closed_if_any`, `hours` (un negocio), `toast_key` |
| `private_rooms.json` | `PrivateRooms` | cuartos ajenos: golpear, forzar, ganzúa, que te encuentren adentro |
| `annoyance.json` | `AnnoyanceSystem` | fastidio: cerrarle el paso, rondarlo, volver a hablarle enseguida |
| `barks.json` | `ChatterSystem` | frases sueltas, charlas entre dos, negativas y llamados ([Barullo](#barullo-y-llamados)) |
| `energy.json` | `Stamina` | energía: correr la gasta, caminar y quedarse quieto la recuperan, comer la llena |
| `economy.json` | `Wallet` | dinero del día: viático, pago por tarea, opciones con `cost` |
| `trust.json` | `Trust` | confianza de cada persona, de `min` a `max` |
| `relations.json` | `Relations` | quién sabe de quién al «preguntar por alguien» |
| `speeches.json` | `Speeches` | asientos, alguien que le habla a la sala, quien atiende en una zona |
| `escort.json` | `EscortSystem` | quien da un encargo lleva al jugador hasta donde empieza |
| `search.json` | `SearchSystem` | alguien busca al jugador si va atrasado con el trabajo |
| `identify.json` | `Identification` | fichas para identificar gente, al estilo Obra Dinn |
| `inspectables.json` | `Inspectable` | objetos examinables (su diálogo en `data/dialogue/obj_<id>.json`) |
| `buildings.json` | `build_world` | edificios dibujados enteros (y relojes de fachada) |

Cada script nombrado tiene arriba, en su comentario, todos los campos de su archivo.

### Claves de texto que pone cada juego

Las de la UI genérica vienen en `translations/jornada.csv` y el juego no las repite. El juego pone:

- **Por persona** `<id>`: `who_<id>` (cómo se lo describe sin conocerlo), `first_<id>`, `last_<id>`, `chr_<id>`
  (nombre completo), `role_<id>`, `bio_<id>`.
- **Por flag**: `flag_<flag>` (título) y `desc_<flag>` (detalle); las deducciones, su `title_key`.
- **Por zona**: `zone_<id>`.
- **Menú**: `ui_menu_subtitle`, `ui_menu_place`, `ui_menu_version` y `ui_menu_continue_tip` (`%d` jornada, `%s` cuándo se guardó).
- **Diario y trabajo**: `toast_journal_hint`, `ui_journal_seal_hint`, `work_panel_title`, `work_pay`,
  `toast_work_failed` y `toast_work_late`.
- **Dinero** (si el juego trae `data/economy.json`): `hud_money` (`%d`, el contador bajo la barra de energía).
- Las que nombren `game.json` (`intro`, `thoughts`, `journal.guide`, `idle_thoughts`...) y los datos (diálogos,
  eventos, frases).

Las frases genéricas de la gente (`dlg_repeat_*`, `dlg_people_*`, `dlg_idle_dismiss`...) vienen en `jornada.csv`; el
juego puede dar la suya por persona o por voz agregando `_<npc>` o `_<voz>` a la clave, y variantes `_1`, `_2`...

## data/game.json

Las reglas del juego. Los sistemas genéricos le preguntan a `GameConfig` (`GameConfig.value("day.start")`) en vez de
nombrar cosas de un juego. Un `"_doc"` en cualquier sección se ignora: sirve para explicar el dato ahí mismo.

```json
{
  "title": "Primer día",
  "scenes": {"menu": "res://scenes/menu/main_menu.tscn", "game": "res://scenes/main.tscn"},
  "ui": {"menu_background": "res://scripts/ui/fondo.gd"},
  "start": {"zone": "plaza", "tile": [21, 12]},
  "day": {"start": "07:00", "end": "13:00", "at_end": "next_day", "first_date": "1952-04-14",
          "reset_kinds": ["state"], "clock_runs_in_dialogue": false},
  "flags": {"has_journal": "journal_owned"},
  "persistent_flags": ["journal_owned"],
  "names_from": "has_journal",
  "suspicion": {"warning": 60, "arrest": 100},
  "intro": {"title": "intro_title", "lines": ["intro_1"], "continue": "intro_continue"},
  "thoughts": {"wake_first": ["think_day_1"], "wake_later": ["think_day_later"]},
  "people": {"outsiders": [], "kids": ["lucia"], "no_surname": ["lucia"], "known_by_surname": [],
             "keeps_name": [], "known_from_start": {"marta": "full"}},
  "special_days": {"feria": {"date": "1952-04-20", "data_dir": "res://data/feria"}}
}
```

| Clave | Qué es |
|---|---|
| `scenes`, `ui.menu_background` | escena del menú y de la partida; un script opcional que dibuja el fondo del menú |
| `start` | zona y celda donde arranca el jugador |
| `day.start`, `day.end` | horario de la jornada (`"HH:MM"`) |
| `day.at_end` | `"loop"` (vuelve al mismo día) o `"next_day"` (el calendario avanza desde `first_date`, `"AAAA-MM-DD"`) |
| `day.reset_kinds` | tipos de flag (`Kind` en minúsculas) que se olvidan al terminar la jornada, salvo `persistent_flags` |
| `day.clock_runs_in_dialogue` | el reloj sigue mientras se habla (quien habla se queda quieto, los demás siguen); por defecto no |
| `flags` | qué flag del juego cumple cada **rol** del framework: `has_journal` (tener el diario), `work_received` (la orden de trabajo de hoy), `work_failed` (no hizo ninguna tarea a la hora de entrega), `all_tasks_done` y `all_tasks_done_again` (las hizo todas, la primera vez y las siguientes), `suspicion_warning` y `suspicion_arrest`. Un rol sin flag no se usa |
| `persistent_flags` | flags que sobreviven al fin de la jornada aunque su tipo se olvide |
| `names_from` | desde cuándo se aprenden nombres: un número de jornada o un rol/flag (ver `GameConfig.unlocked`); antes, cada uno es lo que hace |
| `suspicion` | umbrales de advertencia y de arresto (fin de la jornada con motivo `"arrest"`) |
| `intro` | la tarjeta del principio de la partida |
| `thoughts` | lo que piensa el jugador: `wake_first` (una por jornada, en orden), `wake_later` (después, al azar del día), `journal_kept` (desde la jornada `journal_kept_from`, la primera vez que el diario sigue lleno), `work_order`, `task_done_first` y `task_done_later` |
| `notices` | carteles que frenan el juego al ganar un flag: `[{flag, loop_max?, title, text, button?}]` (`Notices`) |
| `people` | grupos de gente: `outsiders` (de afuera), `kids`, `known_by_surname` (se los nombra por el apellido), `no_surname`, `keeps_name` (no dicen su nombre) y `known_from_start` (`{id: first/last/full}`) |
| `dialogue.repeats_to_snub` | sin `trust.json`: cuántas preguntas repetidas antes de que corte por hoy |
| `dialogue.idle_seconds` | con el reloj andando en las charlas: segundos sin elegir antes de que quien habla se despida (`dlg_idle_dismiss`); 0 = nunca |
| `deductions.manual`, `deductions.think_minutes` | deducciones armadas a mano en «Casos» y lo que cuesta pensar (`place`, `solve`) |
| `journal.hidden_tabs`, `first_tabs`, `tab_names`, `guide` | pestañas del diario y la guía (ver [Diario](#el-diario)) |
| `idle_thoughts` | pensar quieto (`IdleThoughts`): `after_seconds`, `zoom`, `seconds`, `cooldown_minutes`, `key`, `key_prefix` |
| `work.boss`, `work.trust_at_tasks`, `work.trust_from`, `work.trust_after_all_done` | confianza con quien dio la orden según las tareas hechas |
| `special_days` | jornadas especiales (ver abajo) |
| `renamed_ids` | `{id viejo: id nuevo}`: `SaveManager` traduce los guardados anteriores al cambio |

`GameConfig.unlocked(regla)`: una regla «desde cuándo» puede ser un número de jornada o un texto (un rol de `flags` o un
flag); rige cuando el jugador llegó a esa jornada o tiene ese flag. Así un juego de bucle decide por lo que hizo el
jugador y no por el número de día. La usan `names_from`, `relations.json` `from`, `work.trust_from` y la búsqueda.

## El reloj y el día de la marmota

`TimeManager` lleva el reloj (`minutes` desde medianoche, `now_minutes()`, `minute_changed`, `loop_end_reached`). Un
minuto de juego dura un segundo real a velocidad normal (`time_scale`, que el jugador elige en Opciones). El reloj se
frena solo con una charla (salvo `day.clock_runs_in_dialogue`), el diario abierto o la orden de trabajo
(`GameManager.day_clock_held()`); al abrir o cerrar algo así, `GameManager.sync_day_clock()`.

**El mundo sigue al reloj**, no a los cuadros: así una jornada en la que el jugador no interviene es idéntica a la
anterior, a cualquier velocidad y en cualquier máquina.

- `TimeManager.world()` dice cómo avanza el mundo ahora: `CLOCK` (con el reloj andando: lo que camina cada uno, cuándo
  habla y cuánto dura un globo salen de él), `HELD` (el reloj frenado por una charla, el diario o la orden: todo
  quieto) o `FREE` (frenado por otra cosa, como el final del día o una prueba: tiempo real).
- `TimeManager.seconds_since(minuto)`: segundos de juego desde una hora del reloj.
- `TimeManager.advance_minutes(n)` salta el reloj (una tarea, esperar). Cada salto suma `jumps`: quien camina no
  recupera de golpe ese rato, aparece donde tiene que estar.
- Los NPCs caminan por el reloj (`NpcActor.sync_to_clock()`), el barullo habla en minutos fijos del día y los globos
  duran tiempo de juego.
- **`Daily`** reemplaza el azar: `Daily.index(clave, n)`, `Daily.pick(opciones, clave)`, `Daily.range_f(a, b, clave)` y
  `Daily.at_minute(id)` (la clave de `id` en este minuto del día). La misma clave da siempre lo mismo: qué frase dice alguien al
  pasar, adónde deambula, qué negativa da. Si el jugador no hace nada distinto, cada jornada pasa lo mismo a la misma
  hora; si cambia algo (está en otro lugar, pregunta otra cosa), cambia lo que oye.

Para el día de la marmota los diálogos no deberían depender del número de jornada (`loop_min`/`loop_max` existen para
juegos `next_day`): lo que cambia una charla es lo que el jugador sabe o tiene.

## Jornadas especiales

Un día distinto del de siempre, con su gente, sus horarios, sus diálogos, su fecha y su horario (un sueño, un viaje en el
tiempo, una feria). Van en `game.json` `special_days`:

```json
"special_days": {
  "feria": {
    "date": "1952-04-20", "start": "09:00", "end": "12:00",
    "data_dir": "res://data/feria", "hide_regular": false,
    "cast": {"musico": "res://assets/generated_assets/sprites/npcs/musico_sheet.png"},
    "tint": [1.0, 0.95, 0.85],
    "zone_scenes": {"plaza": "res://scenes/zones/plaza_feria.tscn"},
    "keep_objects": []
  }
}
```

- El juego decide cuándo: `LoopManager.next_special_day = "feria"` antes de terminar la jornada; la siguiente es esa.
  Después de ella vuelve un día de los de siempre. `LoopManager.special_day` dice cuál corre (`""` = un día normal) y
  `LoopManager.special()` su configuración.
- `date` (la fecha que ve el jugador, `LoopManager.today()`), `start`/`end` (sin ellos, los de `day`) y `tint` (tiñe el
  mundo).
- `data_dir`: los horarios y diálogos propios del día (`<data_dir>/schedules/<id>.json`, `<data_dir>/dialogue/<id>.json`).
  `LoopManager.data_file(kind, id, ruta_de_siempre)` elige cuál vale hoy. `cast` suma gente que solo existe ese día
  (id → hoja de sprite; su horario y diálogo en `data_dir`).
- `hide_regular: true`: la gente de siempre sin horario propio ese día no aparece, los objetos examinables se van (salvo
  `keep_objects`) y se callan los sistemas del día normal: el plazo del trabajo, la búsqueda, los eventos con hora
  (`LoopManager.is_regular_day()` es falso; los sistemas del juego deberían preguntarlo también).
- `zone_scenes`: `{zona: escena}` carga otra escena para esa zona ese día. Es la misma zona (mismo id y tamaño): los
  horarios, pasos y puertas sirven igual.

`DataValidator` revisa las jornadas especiales (fecha, horario, carpeta, reparto, escenas) y los horarios y diálogos de
su carpeta.

## Gente: horarios

`data/schedules/<id>.json`: `{"entries": [punto, ...]}`, en orden de hora. La hora es la de **llegada**: el NPC sale
antes según el largo real del camino (`ZoneManager.route_length_px`).

```json
{"time": "09:50", "zone": "panaderia", "tile": [7, 6], "face": "up", "doing": "comprar"}
```

| Campo | Qué hace |
|---|---|
| `time`, `zone`, `tile` | a qué hora llega, a qué zona y a qué celda. `"zone": "gone"` = se va (camina hasta la salida más cercana y desaparece) |
| `via` | celdas por las que pasa en el camino |
| `face` | hacia dónde mira al llegar (`up`, `down`, `left`, `right`) |
| `sit` | se sienta en la celda (un banco: es obstáculo; hace falta una celda libre al lado). Usa el cuadro de sentado `<id>_sit.png` |
| `doing`, `item`, `item_at` | qué está haciendo: cada tanto agacha la cabeza; con `item` (un PNG de los objetos) se ve el objeto a `item_at` px de los pies. `NpcActor.doing()` dice qué hace ahora (las frases y discursos con `doing` solo salen mientras lo hace) |
| `roam` | celdas (`[x, y]` o `[x, y, "up"]`) por las que va y viene mientras dura el punto, elegidas con `Daily` |
| `vanish` | al llegar desaparece sin salir de la zona (una trampilla, la boca de un pozo) |
| `boards` | con `"zone": "gone"`, desaparece en el lugar (sube a un vehículo que tiene al lado) |
| `stay_if`, `skip_if` | con alguno de esos flags no sale hacia este punto / lo saltea y sigue al próximo (también si el flag llega en camino) |
| `days`, `weekdays` | solo esas jornadas (números) o días de la semana (`"mon"`..`"sun"`) |

Reglas a la vista del jugador: nadie aparece ni se esfuma lejos de una puerta o un borde; mientras le hablan no se
mueve; si el jugador le cierra el paso espera, lo rodea y, después de varios esquives, pide permiso y pasa. Atrasado,
aparece en su lugar solo si el jugador no lo vio en los últimos minutos.

API de `NpcActor` para el juego: `approach_player()` (viene hasta el jugador entrando por una salida, nunca aparece a
su lado), `begin_detour(zona, px)` / `retarget_detour` / `end_detour()` / `end_detour_in_place()` (salirse del horario
sin perderlo), `hold(true)` (frenarlo), `warp(zona, px)`, `redirect(zona, celda)` (abandona el horario),
`show_bark(texto, color, segundos, estilo)`, `doing()`, `is_sitting()`, `display_name()`.

`python3 addons/jornada/tools/schedule_table.py [--root <proyecto>] [--check]` escribe la tabla `docs/HORARIOS.md`
(dónde está cada uno cada media hora) y revisa orden, zonas y que dos personas no compartan celda al mismo tiempo.

## Diálogos

`data/dialogue/<npc>.json` (y `obj_<id>.json` para los objetos examinables, con el mismo motor):

```json
{"entries": [
  {"id": "greet", "entry": true, "priority": 0, "text_key": "dlg_marta_greet", "options": [
    {"text_key": "opt_marta_first", "method": "ask", "next": "first", "reveals": ["oven_lit"]},
    {"text_key": "opt_marta_who", "method": "ask", "next": "who", "requires": ["journal_owned"]}
  ]},
  {"id": "first", "text_key": "dlg_marta_first", "next": "greet"}
]}
```

Una **entrada** es una línea (≤3 frases). Las que tienen `"entry": true` son puntos de entrada: al hablarle, gana la de
mayor `priority` entre las que cumplen su `condition`. Se encadenan con `next`; `options_of: "<entrada>"` ofrece las
opciones de otra entrada sin copiarlas.

**Condiciones** (en `condition` de una entrada y directo en una opción):

| Campo | Se cumple si... |
|---|---|
| `knowledge` / `knowledge_any` / `not_knowledge` (entradas); `requires` / `requires_any` / `not_requires` (opciones) | tiene todos / alguno / ninguno de esos flags |
| `time_min`, `time_max` | la hora está en esa ventana |
| `suspicion_min`, `suspicion_max` | la sospecha está en ese rango |
| `loop_min`, `loop_max` | el número de jornada está en ese rango |
| `zones` | el jugador está en una de esas zonas |
| `absent` | ninguna de esas personas está en la zona del jugador |
| `unwatched_by` / `watched_by` | ninguno / alguno de esos NPCs está en la zona del jugador (contar algo a solas) |
| `tasks_min`, `tasks_max` | tareas de trabajo hechas hoy |
| `seen_today` | hoy ya se cruzó con esa persona |
| `visited` | ya estuvo alguna vez en alguno de esos lugares |
| `knows_name` / `not_knows_name` | sabe / no sabe cómo se llama esa persona |
| `identified` | esas fichas de `Identification` están confirmadas |
| `energy_below` | la energía es menor que N |
| `after_today` (opciones) | hoy ya eligió alguna de esas opciones o ya oyó esa entrada |
| `cost` / `cant_afford` (opciones) | le alcanza / no le alcanza la plata |
| `needs_names` (opciones) | ya se pueden aprender nombres (la respuesta dice uno) |

**Lo que da una línea u opción**: `reveals` (flags), `suspicion_delta`, `effects` (ids registrados en `WorldEffects`),
`trust` (sube o baja la confianza), `cost` (cobra). Una **opción** lleva `method` (`ask`, `empathy`...): una `ask` ya
contestada hoy no se vuelve a contestar («eso ya se lo contesté»); al insistir, quien habla corta y no habla más hasta el
día siguiente (con `trust.json`, cada repetición más allá de su `patience` baja un nivel). `repeatable: true` (o costo o
efectos) se repite sin problema; `once_per_loop: true` se elige una vez por jornada. Las opciones usadas no
desaparecen: se ven más tenues (`DialogueManager.option_used`).

**Quién habla y nombres**: `speaker_key` (clave del CSV) hace que esa línea la diga otro (una escena con varios: una
votación, una discusión); `sd_key` es una acotación. `learns_name: "first"|"last"|"full"` le enseña al jugador el
nombre de quien habla y `names: {npc: "first"|"last"|"full"}` el de otro que esa línea nombra (salvo antes de
`names_from`). `no_small_talk: true` en una entrada no ofrece «¿cómo se llama?» ni «le quería preguntar por alguien».

**Charla armada por el juego**: `DialogueManager.context = {"quien": "..."}` reemplaza `{quien}` en los textos y
`DialogueManager.start(npc, entrada)` abre exactamente esa entrada. `DialogueManager.abort()` la corta.

**Preguntar por alguien** (`relations.json`, `Relations`): sin `from`, cualquiera habla de cualquiera. Con el archivo:
`from` (desde cuándo), `gates` (qué falta para que hable: una zona, una cerveza; con `refuse` y `entry`), `groups` +
`knows` (hasta dónde conoce cada uno a cada otro: `role`, `name`, `full`; manda la última regla), `ties` + `types`
(lazos que cambian la respuesta: cuántos datos da, si esquiva, qué piensa del otro), `voices` (con qué voz contesta) y
`allowance` (por cuántos vecinos contesta por jornada según la confianza). Cada respuesta da la capa siguiente: qué hace,
un nombre, el nombre completo. Las frases salen del CSV de lo más propio a lo más general
(`rel_<capa>_<persona>_<quien contesta>`, `rel_<capa>_<persona>_<voz>`, `rel_<capa>_<persona>`,
`dlg_people_<capa>_<tipo de lazo>`, `dlg_people_<capa>_<voz>`, `dlg_people_<capa>`; ver
`DialogueManager._about_line`).

**«¿Usted es ...?»**: con un nombre puesto en la ficha de quien tiene enfrente (`Identification`), se le puede
preguntar. Si acierta, el dato queda confirmado; si no, tachado, y la reacción depende del lazo con la verdadera dueña
del nombre (`wrong_name` del tipo en `relations.json`: `snub` se ofende, `friend` cuenta quién es).

**Confianza** (`trust.json`, `Trust`): `min`, `max`, `default.patience` y `people.<id>.patience`. El nivel arranca en 0
cada jornada y mantiene los flags `<persona>_trust_<n>` (ganar uno sube el nivel). En `min` no habla más ese día. Se ve
en una barra bajo el retrato; con confianza alta o baja se usa el retrato feliz o enojado si existe (`portraits/happy/<id>_happy.png`, `portraits/angry/<id>_angry.png`).

**Despedida por esperar**: con `day.clock_runs_in_dialogue` y `dialogue.idle_seconds`, si el jugador no elige, quien
habla se despide (`dlg_idle_dismiss[_<npc>|_<voz>]`) y se va.

## Barullo y llamados

`data/barks.json` (`ChatterSystem`):

- `solo`: `{npc: [{key, zones?, names?, doing?}]}` frases sueltas, cada uno en minutos fijos de su agenda (entrar a la
  zona un minuto antes o después no cambia qué dice). Solo habla quien está en pantalla.
- `pairs` (`"a|b": [{a, b}]`) y `generic`: charlas cuando dos se cruzan.
- `brush`, `brush_npc`: la frase corta de quien no tiene nada que decir.
- `settings` (claves de `ChatterSystem.DEFAULTS`: ritmo, cuántos globos a la vez, duración) y `settings.zones.<zona>`.
- Una línea con `names` (`{npc: "first"|"last"|"full"}`): si el jugador hace clic en el nombre resaltado y esa persona
  está a la vista, lo aprende.

**Llamados** (`calls`): un NPC le habla al jugador al acercarse a un lugar, una vez por jornada.

| Campo | Qué hace |
|---|---|
| `id`, `npc`, `key` | el llamado, quién y qué dice |
| `zone`, `tile`, `radius`, `min_distance` | dónde: a menos de `radius` px de la celda (y a más de `min_distance`). Sin `zone`, el lugar es el NPC mismo: le habla a quien se le acerca, esté donde esté (salvo en `except_zones`) |
| `npc_zone` | el NPC está en otra zona (o lista): se lo oye a través de la puerta, sin verlo |
| `time_min`, `time_max`, `loop_min`, `loop_max`, `knowledge`, `not_knowledge` | cuándo vale |
| `reveals` | flags que da |
| `dialogue: true` | abre el diálogo del NPC en vez de decir una frase |
| `approach: true` | con `dialogue`: entra caminando hasta el jugador y habla al llegar |
| `think_key` | contesta el jugador solo, en voz alta |
| `or_after_seconds` | también sale si el jugador lleva ese tiempo en la zona sin acercarse |
| `after_seconds` | no sale hasta que el jugador lleve ese tiempo en la zona (primero ve dónde está) |
| `first: true` | es lo primero que pasa en la zona: si el jugador va a una puerta o toca algo antes, sale en ese momento |
| `sfx`, `alert`, `wait`, `player_key`, `sfx_after` | antes de hablar, con el jugador quieto: un sonido (golpes en la puerta), un «!» sobre el jugador, una espera, lo que contesta el jugador y otro sonido (la puerta que se abre) |

Globos (`ui/speech_bubbles.gd`): no se pisan ni se salen de la pantalla (si no hay lugar, el de menos prioridad
espera). `NpcActor.show_bark(texto, color, segundos, estilo)`: `"speech"` (`UiStyle.ACCENT`, `"accent"`: le hablan
al jugador) o `"address"` (recita para un público); `PlayerController.think()` usa `"thought"`.

## Otros sistemas de la gente

- **Escolta** (`escort.json`, `EscortSystem`): al ganar `start.flag` (salvo con `start.unless`, desde `start.from_zones`),
  `npc` lleva al jugador a `destination`; si se atrasa lo llama (`call_keys`), lo busca (`nag_entries`) y al final lo
  lleva con fundido (`force_entry`, `force_suspicion`). `tour.stops` sigue de parada en parada (`zone`, `tile`,
  `player_tile`, `entry`). Con `"guided": true` el jugador no se puede ir: camina solo detrás de ella
  (`PlayerController.guide_to`) y cruza las puertas y bordes por donde ella pasó; `guided_barks` (`{zona: clave}`) es
  lo que dice al entrar a cada zona. Si el jugador empieza a trabajar antes, la escolta termina. Mientras lleva al
  jugador nada cuenta como fastidio (`EscortSystem.is_leading`).
- **Búsqueda** (`search.json`, `SearchSystem` + `Sightings`): en cada `checkpoints` (hora, tareas mínimas), si el
  jugador va atrasado, `npc` lo busca y llega solo adonde alguien pudo haberlo visto, y lo dice («{quien} me avisó que lo
  vio por {lugar}»). `max_name_chars` y `max_place_chars` fijan el peor caso que revisa el validador.
- **Discursos y asientos** (`speeches.json`, `Speeches`): `seats` (por objeto, los puestos donde sentarse; E sienta y
  moverse levanta), `speeches` (alguien que le habla a la sala, si quiere solo mientras hace algo, `doing`; escucharlo
  sentado `listen_minutes` da `reveals` y lo trae a hablar) y `service` (quien atiende viene cuando el jugador se sienta).
- **Cuartos ajenos** (`private_rooms.json`, `PrivateRooms`): con el ocupante adentro se golpea (diálogo
  `door_<ocupante>.json`); afuera, se fuerza (y si alguien lo ve, sospecha y la señal `seen_forcing` con las veces del
  día, para que el juego decida qué pasa). `admits: false`, `needs` (flags sin los que no se fuerza), `quiet_flag` (la
  ganzúa), y la entrada `door_<ocupante>_caught` para que el dueño eche al que encuentra adentro.
- **Testigos** (`witness.json`, `WitnessManager`): `rules` `{flag, actor, zone, time_min, time_max, minutes}`: ver a
  alguien ahí da el flag. El pensamiento `think_<flag>` puede decir `{quien}` (la persona como la conoce el jugador).
- **Fastidio** (`annoyance.json`, `AnnoyanceSystem`): por NPC, `gesture_key`, `word_key` y `snap_flag` (a la tercera,
  el NPC salta y abre su entrada `<npc>_snap`).
- **Carteles** (`game.json` `notices`, `Notices`): frenan el juego al ganar un flag, apenas termina la charla.

## El diario

`data/journal.json` (`JournalManager` y `ui/journal.gd`, tecla J). Recordar no es anotar: el jugador recuerda todo lo
que averigua, pero en el diario solo figura lo que pasó teniéndolo (rol `has_journal`); lo de antes entra cuando vuelve a
enterarse. Cada pista anotada guarda de dónde salió (`JournalManager.source_text`). Lo anotado sobrevive a las
jornadas y se guarda con la partida.

- `people`: fichas `{id, name_key, role_key, bio_key, flags, heard}`; `groups`, `category_group`.
- `deductions`: `{id, title_key, all_of, any_of, auto?}`. Las da `DeductionSystem` (un diálogo no puede).
- `roster`: una lista de gente que se desbloquea con `unlock_flag` (pestaña propia).
- `map_cells`, `zone_parent`: el mapa (dónde va cada exterior, de qué exterior cuelga cada interior).
- `questions`: lo que el jugador se pregunta, `{id, text_key, hint_key, answer_key, opens, answered_by}`. Se abre con
  cualquiera de `opens` y queda respondida con cualquiera de `answered_by` (conviene que no se olviden entre jornadas).
  Pestaña «Preguntas» (abiertas primero, con lo que piensa hacer, y las respondidas); avisa al abrirse y al responderse.
  `JournalManager.questions()`, `question_state(q)`, `open_question_count()`, señal `question_changed`.

Pestañas: `evidence`, `people`, `deductions`, `map`, `roster`, `identify`, `cases`, `questions`. En `game.json`
`journal`: `hidden_tabs` (no se muestran), `first_tabs` (van primero) y `tab_names` (`{pestaña: clave}`).

**Guía** (`journal.guide`): el diario se abre solo, una vez por partida, al conseguirlo (`on_get`), con la primera pista
(`first_clue`) y con el primer nombre (`first_name`), y recorre sus `steps`: cada uno abre la pestaña `tab` (si no se ve,
el paso no va), oscurece todo menos `target` (`panel`, `tab`, `clue`, `threads`, `row`, `field`), lo señala con una flecha
y lo explica con `tip` (`%s` = la pista o el nombre). E sigue, Esc salta; al cerrar, el jugador piensa `think`.

**Casos** (`Cases`, pestaña `cases`): con `deductions.manual`, el jugador arrastra pistas a hilos y, cuando un hilo
tiene exactamente las de una deducción, la resuelve. Lo pensado (`deductions.think_minutes`) se cobra al cerrar el
diario. Una pista que ya no sirve para ningún caso queda como usada.

**Pensar quieto** (`idle_thoughts`, autoload `IdleThoughts`): si el jugador se queda `after_seconds` reales sin tocar
nada y tiene un caso con todas sus piezas anotadas sin armar, la cámara se acerca (`zoom`, propiedad `PlayerCamera.focus`) y
piensa en ese caso (`key_prefix` + deducción, o `key` con `{caso}`). Cada caso una vez por jornada, `cooldown_minutes`
entre pensamientos; cualquier tecla corta el acercamiento.

**Identificación** (`identify.json`, `Identification`): una ficha por persona con varios datos (`fields`: nombre,
apellido, ocupación...); las opciones se habilitan con flags o con lo que el diario sabe del nombre de alguien
(`journal_bit`); una ficha con `person` aparece cuando el jugador vio a esa persona. Se confirman de a `batch` fichas
enteras bien sin decir cuál está mal. Cada ficha puede traer `clues` (`{key, requires_any}`) y un renglón de notas
libres del jugador (N o clic; no cuenta para confirmar). Los nombres de las fichas se resaltan en lo que se dice: en un
diálogo se anotan solos, en un globo con un clic. Un nombre puesto en la ficha de alguien se ve con duda sobre su
cabeza («Marta?»).

## Trabajo, energía y dinero

- `work.json` (`WorkManager`): `tasks` (`{id, name_key, zone, duration, minigame, mandatory?, reveals?, fail_loses_trust?}`;
  `reveals`: `[{flag, requires?, after?}]`, lo que se descubre al hacerla),
  `deadline` (sin él no hay plazo), `pace` (`share_until_all_done`: mientras nunca terminó todas, cada tarea se lleva lo
  que queda hasta la entrega repartido entre las pendientes). La orden del día es el rol `work_received`. Ajustes con
  valores por defecto: `suspicion_on_complete` (−8), `suspicion_on_fail` (15: ninguna tarea a la hora de entrega, y el
  rol `work_failed`), `veteran_from` (6: desde esa jornada, una tarea ya dominada se hace sin minijuego por
  `veteran_fraction`, 0,6, de su duración; 0 lo apaga). Destreza: cada tarea cuesta 100/80/60 % de su duración según las
  veces que se resolvió bien.
- Minijuegos: extender `Minigame` (`work/minigame.gd`), nombrar el script en la tarea. `_briefing_key` muestra un
  cartel antes de empezar; `finished(success, data)` con `extra_minutes`, `forced`, `cancelled`, `toast_key`.
- `energy.json` (`Stamina`): `max`, `start`, costos y recuperación, `foods` (cada alimento es el efecto `eat_<id>`).
  Las pruebas fijan la energía con `Stamina.set_value`.
- `economy.json` (`Wallet`): `start`, `viatico` (al ganar `viatico_flag`), `pay_per_task`.

## Puntos de extensión

- `WorldEffects.register(id, func)`: efectos que disparan diálogos y objetos (`"effects": ["id"]`).
- `LoopManager.end_of_day_handler` (`func(motivo)`) y `LoopManager.end_day(motivo)`: qué pasa al terminar la jornada
  (`"time"`, `"arrest"` o los del juego; por defecto, la siguiente). `LoopManager.next_wake_thought` elige qué piensa al
  despertar. Señales `loop_started`, `knowledge_gained`, `knowledge_repeated`, `game_reset`.
- `LoopManager.next_special_day`: la jornada especial que viene.
- `SaveManager.register_section(clave, guardar, cargar)`: lo que el juego guarda en la partida.
- `TimedEvents.register_sound_source(nombre, func)`: de dónde sale un sonido de `events.json` (`"source"`).
- Señal `PrivateRooms.seen_forcing(cuarto, testigo, veces)`: qué pasa cuando lo ven forzando una puerta.
- Horarios: `"stay_if"`, `"skip_if"`, `"days"`, `"weekdays"`; eventos: `"days"` y `"weekdays"`.
- Diario: pestaña `"roster"` en `journal.json` (una lista que se desbloquea con un flag).
- Minijuegos de trabajo: `Minigame`.

## Mundo

`godot --headless --path . res://addons/jornada/tools/build_world.tscn` arma el TileSet, una escena por zona y la
escena de la partida a partir de los datos (repetir con `--import` en el medio si cambian los PNG de tiles).

- `data/world.json`: lista de tiles (orden = columna del atlas; `solid`, `window`, `sun`), piezas de puertas,
  estilos de pared y techo, el seto del borde de los exteriores, bordes entre suelos, objetos con su base de colisión,
  rutas y la lista de personajes. Un objeto con collider `[0, 0]` se camina por encima; `"shadow": false` no lleva
  sombra; `"wall": true` cuelga de la pared del fondo (se ordena por la pared, no por sus pies); `"flat": true` se
  dibuja debajo de quien lo pisa; `"frames"`/`"fps"` lo animan; `"raise"` lo apoya más arriba (sobre un mostrador).
- **Rejas**: un objeto con `closed_if_any` (lista de flags) y `open` (otro dibujo) es sólido mientras el jugador tenga
  alguno de esos flags, abierto y con el otro dibujo si no; la navegación de los NPCs lo pasa siempre (`Prop.is_gate`,
  `is_closed`).
- **Muebles con profundidad**: en un interior, la base de un mueble bajo y ancho (mesa, mostrador, banco, escritorio)
  la calcula `build_world` a partir de su dibujo (`Prop.furniture_base`): tan honda como para que, detrás, el mueble
  tape solo los pies y las piernas del personaje (12 px). `"props": {"depth": {"cover", "cap", "min_width",
  "max_height"}}` en `world.json` cambia los valores; `"depth": false` lo apaga. Lo que queda a menos de un tile de una
  pared estira su base hasta tocarla (`Prop.wall_reach`).
- **Mostradores** (`counters` de un interior): la fila es el tile sólido de `parts.counter`. Con
  `parts.counter_sprites` ([izquierda, medio, derecha]) encima va una pieza que tapa las piernas de quien está detrás;
  lo que se apoya encima (`raise`) sube `parts.counter_lift` px con la tapa.
- `data/zones.json`: cada zona con su escena, tamaño, layout y conexiones (puertas con `door_tile`, o bordes con
  `kind: "edge"`). Una zona es interior si su layout lo es (o `"exterior": false`). Las celdas a las que no se llega
  desde ninguna salida cuentan como obstáculo.
- Layouts: `grid` (filas de caracteres + `legend`), `interior` (cuarto con pared norte, ventanas, puertas a cuartos
  hijos, mostradores y salida al sur) u `outdoor` (suelo, rectángulos `fills`, edificios y seto). Todos aceptan
  `props`, `spots` (puestos de trabajo) y `nodes` (nodos con script del juego).
- Bordes entre exteriores (`ZoneManager.walk_through`): se cruza caminando; la llegada cae en una celda que se pisa y,
  si el jugador igual queda fuera del mapa, vuelve adentro o pasa a la zona vecina.

## Cámara, globos y nombres

- `world/player_camera.gd`: la cámara va pegada al jugador en cada cuadro dibujado, hace su propio límite contra los
  bordes del mapa (centra las zonas más chicas que la pantalla) y redondea su posición para que el mundo se dibuje
  siempre desde un píxel entero (con zooms no enteros, como 1,5, evita que todo tiemble). Zooms en `PlayerCamera.ZOOMS`
  (tecla Z); la propiedad `focus` (1 = nada) la acerca un rato sobre el zoom elegido.
- Los nombres sobre la cabeza de cada personaje salen solo al pasar el mouse (`UiStyle.name_tag()`): lo que el jugador
  sabe de esa persona («El del abrigo gris» hasta saber cómo se llama). La N los muestra todos (versiones de prueba).

## Arte

`tools/pixel/` es una librería de Python (Pillow) para dibujar con la misma paleta y formato:

- `pixel.core`: paleta, `Canvas` (formas + contorno), `noise`, `save_sheet` (la hoja de personaje que lee
  `world/character_frames.gd`, 15 cuadros de 16×32).
- `pixel.figures`: personajes y retratos **por descripción** (`build_frames(desc)`, `portrait(desc, seed)`); el
  vocabulario está al principio del archivo.
- `pixel.sit`: el cuadro de sentado de cada hoja (`<id>_sit.png`).
- `pixel.skin`: la piel por defecto de la UI (`python3 addons/jornada/tools/pixel/skin.py`).

Rutas que usa el framework: `assets/generated_assets/sprites/protagonist_sheet.png`,
`.../sprites/npcs/<id>_sheet.png`, `.../portraits/<id>.png` (y `portraits/happy/<id>_happy.png`, `portraits/angry/<id>_angry.png` si los hay); tiles,
objetos y edificios donde diga `world.json`.

## Validación

`DataValidator.validate_all()` corre al cargar la partida en builds debug (no en el menú) y cuenta errores: dice
«diálogos OK» si no hay ninguno. Revisa flags (contra `KnowledgeRegistry`), claves del CSV (incluidos los `tr("...")`
literales de los scripts del juego y del framework), `next` de los diálogos, condiciones que nombran gente, zonas o
fichas, efectos registrados, horarios (orden, zonas, celdas libres, asientos), celdas de aparición, `game.json` (roles,
gente, intro, pensamientos, guía, `idle_thoughts`), jornadas especiales, preguntas del diario, cerraduras, rejas,
cuartos ajenos, examinables, trabajo, fastidio, barullo y llamados, fichas, búsqueda, escolta, carteles, música, energía,
confianza, relaciones y discursos. Un dato que falta hace fallar acá, no en medio de una partida.

## Pruebas

`testkit/runner.gd` corre cada `test_*` de `res://tests/test_*.gd` (`test_slow_*` solo con `--slow`) y antes revisa
que todo compile. `testkit/test_case.gd` trae asserts y esperas (`frames`, `seconds`, `until`, `press`);
`testkit/game_case.gd` suma `start_game`, `set_clock`, `go`, `speed_up`, `reachable` y dos revisiones de todo el
mundo para correr en cada juego: `unreachable_interactables` (lo que se toca con E se alcanza desde un lugar libre) y
`shallow_furniture` (los muebles bajos tienen la profundidad de su dibujo).

```bash
godot --headless --fixed-fps 60 --path . -s res://addons/jornada/testkit/runner.gd -- [--slow] [filtro]
```

`--fixed-fps 60`: cada cuadro dura lo mismo aunque la máquina tarde más o menos, así lo que pasa no depende de la carga
y dos jornadas se pueden comparar exactas.

## Juego de ejemplo

`examples/primer_dia/` es un proyecto aparte que usa este mismo addon (enlace simbólico): `tools/make_art.py` dibuja
el arte con `pixel`, los datos están a mano y `run_tests.sh` corre sus pruebas. Muestra la jornada `next_day` con
calendario, horarios con `doing`, diálogos con condiciones, el diario con una pregunta, una jornada especial (la feria
del domingo) y las revisiones del testkit. Si el ejemplo anda sin tocar el addon, el framework sirve para algo más que
el juego para el que nació.
