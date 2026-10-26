class_name NpcActor
extends StaticBody2D
## NPC interactuable que sigue su horario (data/schedules/<npc_id>.json, canon 02).
## Origen del nodo = pies. Camina en línea recta entre puntos; al cambiar de zona sale por la
## puerta y reaparece en la otra. Solo existe para el jugador si está en su misma zona.
## El diálogo sale de data/dialogue/<npc_id>.json.

## Un poco más lento que el jugador (80 px/s): los vecinos caminan sin apuro.
const WALK_SPEED: float = 70.0
## Nunca empuja al jugador: se detiene a esta distancia de sus pies (x, y en px), espera y luego lo rodea.
const PLAYER_GAP: Vector2 = Vector2(13.0, 9.0)
const WAIT_BEFORE_SIDESTEP: float = 0.9
## Al aparecer por una puerta o un borde espera a que no haya nadie encima (hasta MAX_ARRIVAL_WAIT s).
const ARRIVAL_CLEARANCE: Vector2 = Vector2(18.0, 12.0)
const MAX_ARRIVAL_WAIT: float = 5.0
## Minutos de juego de retraso tolerados antes de que el NPC aparezca en su sitio (los eventos del canon son fijos).
const LATE_GRACE: int = 3
## Frases y nombres sobre la cabeza se dibujan por encima del mundo.
const TEXT_Z: int = 100
const NAME_TAG_Y: float = -50.0
## Alto de un renglón de nombres (el recuadro con su borde) cuando hay que apilarlos.
const NAME_TAG_ROW: float = 14.0
const FACES: Dictionary = {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}

@export var npc_id: String = ""
@export var sheet: Texture2D
## Falso: camina su horario pero no se le puede hablar. Hoy todos son interactivos: el que no tiene nada que
## decir (extras, pasajeros, o un NPC fuera de sus horas) contesta con una frase corta (ChatterSystem.brush_off).
@export var interactive: bool = true

var zone: String = ""

## Dirección en la que mira (para visión §10).
func facing_vector() -> Vector2:
	return _facing.normalized() if _facing.length() > 0.01 else Vector2.DOWN


var _entries: Array = []        # {minutes, zone, tile, via}
var _entry_index: int = -1
var _route: Array = []          # {pos, zone?, instant?}
var _facing: Vector2 = Vector2.DOWN
var _talking: bool = false
var _blocked_for: float = 0.0
var _block_reported: bool = false
var _bark: Label
var _bark_tween: Tween
var _name_tag: PanelContainer
var _name_label: Label
var _name_rows: int = 0    # renglones que subió para no pisarse con otro nombre
var _detour: bool = false       # en un desvío (SearchSystem): no sigue el horario hasta end_detour()
var _all_names: bool = false    # tecla N (depuración): nombres de todos siempre a la vista
var _text_drop: float = 0.0     # animales (el perro): nombre, frase y [E] bajan hasta donde empieza el dibujo

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _prompt: InteractPrompt = $Prompt
@onready var _area: Area2D = $InteractArea
@onready var _body_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("npc_actors")
	_sprite.sprite_frames = CharacterFrames.build(sheet)
	_sprite.play(&"idle_down")
	var top: int = sheet.get_image().get_used_rect().position.y
	_text_drop = top if top >= 16 else 0.0
	_prompt.position.y += _text_drop
	PixelLight.add_blob(self, Vector2i(12, 4))
	_add_name_tag()
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	_load_schedule()
	if not _entries.is_empty():
		_entry_index = _entry_at(TimeManager.now_minutes())
		_place_at(_entries[_entry_index])
		_on_minute_changed(0, 0)   # si ya debería estar en camino a su próximo punto, sale ahora
	TimeManager.minute_changed.connect(_on_minute_changed)
	ZoneManager.zone_changed.connect(_on_zone_changed)
	_refresh_presence()


func _exit_tree() -> void:
	DialogueManager.dialogue_started.disconnect(_on_dialogue_started)
	DialogueManager.dialogue_ended.disconnect(_on_dialogue_ended)
	TimeManager.minute_changed.disconnect(_on_minute_changed)
	ZoneManager.zone_changed.disconnect(_on_zone_changed)


func interact() -> void:
	if not DialogueManager.has_dialogue(npc_id) or not DialogueManager.start(npc_id):
		if ZoneManager.player != null:
			_facing = ZoneManager.player.global_position - global_position
		ChatterSystem.brush_off(self)


func _physics_process(delta: float) -> void:
	if is_barking():
		_bark.self_modulate.a = ChatterSystem.alpha_for(global_position)
	if _name_tag != null:
		_name_tag.visible = (_all_names or _mouse_over()) and not is_barking()
		if _name_tag.visible:
			_set_name_text(_display_name())   # cambia apenas aprende el nombre
	# Mientras habla con el jugador se queda quieto: el horario se retoma al terminar.
	if _talking or _route.is_empty():
		CharacterFrames.apply(_sprite, _facing, 0.0)
		return
	var step: Dictionary = _route[0]
	if step.get("instant", false):
		# Si va a aparecer encima del jugador (una puerta, un borde), espera a que se despeje: nunca lo empuja.
		if step.has("pos") and _player_near(step["pos"], ARRIVAL_CLEARANCE) and _blocked_for < MAX_ARRIVAL_WAIT:
			_blocked_for += delta
			return
		_blocked_for = 0.0
		zone = step["zone"]
		if step.has("pos"):
			position = step["pos"]
			reset_physics_interpolation()
		_route.pop_front()
		_refresh_presence()
		return
	var target: Vector2 = step["pos"]
	var next: Vector2 = position.move_toward(target, WALK_SPEED * delta)
	# El jugador manda: si el paso lo metería en el jugador, se detiene (no lo empuja) y, si el paso sigue cerrado, lo rodea.
	if _player_near(next, PLAYER_GAP) and _gets_closer_to_player(next):
		_blocked_for += delta
		_facing = ZoneManager.player.global_position - position
		CharacterFrames.apply(_sprite, _facing, 0.0)
		if _blocked_for >= WAIT_BEFORE_SIDESTEP and not _block_reported:
			_block_reported = true
			AnnoyanceSystem.bump(npc_id, "blocked")   # cerrarle el paso lo fastidia
		if _blocked_for >= WAIT_BEFORE_SIDESTEP:
			_sidestep(target)
			_blocked_for = 0.0
		return
	_blocked_for = 0.0
	_block_reported = false
	var before: Vector2 = position
	position = next
	var moved: Vector2 = position - before
	if moved != Vector2.ZERO:
		_facing = moved
	CharacterFrames.apply(_sprite, _facing, moved.length() / delta)
	if position.is_equal_approx(target):
		_route.pop_front()
		if _route.is_empty():
			_facing = _arrival_facing()  # al llegar queda de frente, o hacia donde diga el horario ("face")


## ¿Este paso acerca al NPC al jugador? (Si ya está pegado y se aleja, puede seguir.)
func _gets_closer_to_player(next: Vector2) -> bool:
	var player: PlayerController = ZoneManager.player
	return player != null and (player.global_position - next).length() < (player.global_position - position).length()


## ¿Está el jugador a menos de `gap` (x, y) de los pies de este punto?
func _player_near(at: Vector2, gap: Vector2) -> bool:
	var player: PlayerController = ZoneManager.player
	if player == null or zone != ZoneManager.current_zone:
		return false
	var d: Vector2 = (player.global_position - at).abs()
	return d.x < gap.x and d.y < gap.y


## Da un paso al costado (hacia el lado libre) para esquivar al jugador y sigue con su camino.
func _sidestep(target: Vector2) -> void:
	var heading: Vector2 = (target - position).normalized()
	var side: Vector2 = Vector2(-heading.y, heading.x)
	for sign_value in [1.0, -1.0]:
		var candidate: Vector2 = position + side * sign_value * PLAYER_GAP.x * 1.3
		var cell := Vector2i(floori(candidate.x / ZoneManager.TILE), floori((candidate.y - 1.0) / ZoneManager.TILE))
		if not ZoneManager.is_cell_solid(zone, cell) and not _player_near(candidate, PLAYER_GAP):
			_route.insert(0, {"pos": candidate})
			return


## Si el jugador acaba de aparecer encima (entró por una puerta), se corre a la celda libre más cercana:
## nunca comparten lugar. Sigue después con su camino.
func step_aside_for_player() -> void:
	if zone != ZoneManager.current_zone or not _player_near(position, ARRIVAL_CLEARANCE):
		return
	var from_cell: Vector2i = ZoneManager.cell_of(position)
	var best: Vector2i = Vector2i(-1, -1)
	var best_distance: float = INF
	for radius in range(1, 6):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var cell := Vector2i(from_cell.x + dx, from_cell.y + dy)
				if ZoneManager.is_cell_solid(zone, cell) or _player_near(ZoneManager.tile_px(cell), PLAYER_GAP * 1.6):
					continue
				var d: float = Vector2(dx, dy).length()
				if d < best_distance:
					best_distance = d
					best = cell
		if best.x >= 0:
			break
	if best.x >= 0:
		position = ZoneManager.tile_px(best)


func is_talking() -> bool:
	return _talking


func is_barking() -> bool:
	return _bark != null and _bark.modulate.a > 0.01


## Frase o gesto sobre la cabeza (fastidio, comentarios, barullo). `seconds` = tiempo antes de desvanecerse.
## La opacidad por distancia al jugador (ChatterSystem.alpha_for) va en self_modulate; el desvanecido, en modulate.
func show_bark(text: String, color: Color = UiStyle.ACCENT, seconds: float = 1.6) -> void:
	if _bark == null:
		_bark = Label.new()
		_bark.custom_minimum_size = Vector2(200, 0)
		_bark.size = Vector2(200, 12)
		_bark.position = Vector2(-100, -66 + _text_drop)
		_bark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_bark.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_bark.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_bark.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_bark.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.05))
		_bark.add_theme_constant_override("outline_size", 4)
		_bark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bark.z_index = TEXT_Z   # por encima de techos y árboles que estén más al sur
		add_child(_bark)
	_bark.text = text
	_bark.add_theme_color_override("font_color", color)
	_bark.modulate.a = 1.0
	_bark.self_modulate.a = ChatterSystem.alpha_for(global_position)
	if _bark_tween != null:
		_bark_tween.kill()
	_bark_tween = create_tween()
	_bark_tween.tween_interval(seconds)
	_bark_tween.tween_property(_bark, "modulate:a", 0.0, 0.4)


func _on_dialogue_started(started_id: String) -> void:
	if started_id != npc_id:
		return
	_talking = true
	if ZoneManager.player != null and zone == ZoneManager.current_zone:
		_facing = ZoneManager.player.global_position - global_position
		ZoneManager.player.face_towards(global_position)


func _on_dialogue_ended(ended_id: String) -> void:
	if ended_id == npc_id:
		_talking = false
		_facing = _arrival_facing() if _route.is_empty() else Vector2.DOWN


func _load_schedule() -> void:
	var path: String = "res://data/schedules/%s.json" % npc_id
	if not FileAccess.file_exists(path):
		push_warning("NpcActor %s: sin horario (%s)" % [npc_id, path])
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for raw: Dictionary in parsed.get("entries", []):
		if not GameConfig.matches_day(raw, LoopManager.loop_number):
			continue   # "days" / "weekdays": este punto no es de hoy
		var tile: Array = raw.get("tile", [0, 0])
		var via: Array[Vector2i] = []
		for v: Array in raw.get("via", []):
			via.append(Vector2i(v[0], v[1]))
		var arrive_at: int = TimeManager.parse_clock(raw["time"])
		_entries.append({
			"minutes": arrive_at,
			"depart": arrive_at,
			"boards": raw.get("boards", false),
			"stay_if": raw.get("stay_if", []),
			"zone": raw["zone"],
			"tile": Vector2i(tile[0], tile[1]),
			"via": via,
			"face": raw.get("face", "down"),
		})
	_compute_departures()


## La hora de cada punto del horario es la de LLEGADA (canon 02: "12:15 Brandt come en la Zur Pinie").
## Cada NPC sale antes, según el largo real del camino desde el punto anterior.
func _compute_departures() -> void:
	for i in range(1, _entries.size()):
		var prev: Dictionary = _entries[i - 1]
		var entry: Dictionary = _entries[i]
		if entry["zone"] == ZoneManager.GONE:
			continue   # se va a la hora indicada (caminando hasta una salida, ver _plan_route)
		var px: float
		if prev["zone"] == ZoneManager.GONE:
			# vuelve de afuera: entra por un borde o una puerta y camina hasta su lugar, así que sale antes
			var door: Vector2 = _entrance_px(entry["zone"], ZoneManager.tile_px(entry["tile"]))
			px = ZoneManager.route_length_px(entry["zone"], door, entry["zone"], ZoneManager.tile_px(entry["tile"]))
		else:
			px = ZoneManager.route_length_px(prev["zone"], ZoneManager.tile_px(prev["tile"]), entry["zone"], ZoneManager.tile_px(entry["tile"]))
		var travel_minutes: int = ceili(px / WALK_SPEED * TimeManager.time_scale) + 1
		entry["depart"] = maxi(prev["minutes"], entry["minutes"] - travel_minutes)


## Último punto del horario con hora <= now. `key` = "minutes" (ya llegó) o "depart" (ya salió).
func _entry_at(now: int, key: String = "minutes") -> int:
	var idx: int = 0
	for i in _entries.size():
		if _entries[i][key] <= now:
			idx = i
	return idx


## Hacia dónde mira al llegar a su punto: "face" del horario (up, down, left, right; los de la barra, a la barra).
func _arrival_facing() -> Vector2:
	if _detour or _entry_index < 0 or _entry_index >= _entries.size():
		return Vector2.DOWN
	return FACES.get(_entries[_entry_index].get("face", "down"), Vector2.DOWN)


func _place_at(entry: Dictionary) -> void:
	_facing = FACES.get(entry.get("face", "down"), Vector2.DOWN)
	zone = entry["zone"]
	position = ZoneManager.tile_px(entry["tile"])
	reset_physics_interpolation()   # aparece de golpe: que no se dibuje deslizándose desde donde estaba
	_route.clear()


## Viene hasta el jugador como llega cualquiera (un arresto, un aviso urgente): si está en otra zona, entra por la
## puerta o el borde de la zona del jugador que le quede más cerca y camina; nunca aparece a su lado. Es un desvío:
## end_detour() lo devuelve a su horario. Quien lo llama mira la distancia para saber cuándo llegó.
func approach_player() -> void:
	var player: Node2D = ZoneManager.player
	if player == null:
		return
	_detour = true
	_route.clear()
	_blocked_for = 0.0
	if zone != ZoneManager.current_zone:
		var door: Vector2 = _entrance_px(ZoneManager.current_zone, player.global_position)
		_route.append({"instant": true, "zone": ZoneManager.current_zone, "pos": door})
		_append_path(ZoneManager.current_zone, door, player.global_position)
	else:
		_append_path(zone, position, player.global_position)


func _on_minute_changed(_hour: int, _minute: int) -> void:
	if _entries.is_empty() or _detour:
		return
	var idx: int = _entry_at(TimeManager.now_minutes(), "depart")
	if idx != _entry_index:
		_entry_index = idx
		# "stay_if": no sale hacia este punto si se cumple alguno de esos flags (en Rabenholz, quien sube al 409 se
		# queda esperando en el andén si el tren no sale).
		if (_entries[idx].get("stay_if", []) as Array).any(func(f: String) -> bool: return LoopManager.has_knowledge(f)):
			return
		_plan_route(_entries[idx])
		return
	# El jugador puede entretenerlo, pero no desordenar el día: pasados LATE_GRACE minutos de su hora aparece en su sitio.
	# Solo si el jugador no lo ve (ni donde está ni adonde va): si no, se esfumaría delante suyo (Baum después de
	# una charla en el Rathaus). A la vista, llega caminando aunque llegue tarde.
	var entry: Dictionary = _entries[idx]
	var watched: bool = zone == ZoneManager.current_zone or entry["zone"] == ZoneManager.current_zone
	if not _route.is_empty() and not entry.get("no_snap", false) and entry["zone"] != ZoneManager.GONE \
			and not watched and TimeManager.now_minutes() - int(entry["minutes"]) >= LATE_GRACE:
		_place_at(entry)
		_refresh_presence()


## Desvío: va a `px` (pies) de `zone_id` y se queda ahí sin tocar el horario, que se retoma con end_detour() (quien busca
## al jugador, el mensajero). Mientras dura no replanifica ni aparece de golpe en su sitio.
func begin_detour(zone_id: String, px: Vector2) -> void:
	_detour = true
	_route.clear()
	_blocked_for = 0.0
	_plan_route({"zone": zone_id, "tile": ZoneManager.cell_of(px), "via": [] as Array[Vector2i]})


## Cambia el destino dentro de la zona en que está (p. ej. el jugador se movió).
func retarget_detour(px: Vector2) -> void:
	if not _detour:
		return
	_route.clear()
	_append_path(zone, position, px)


func end_detour() -> void:
	if not _detour:
		return
	_detour = false
	if _entries.is_empty():
		return
	_entry_index = _entry_at(TimeManager.now_minutes(), "depart")
	_plan_route(_entries[_entry_index])


func is_on_detour() -> bool:
	return _detour


## ¿Terminó de caminar? (sin pasos pendientes)
func is_idle() -> bool:
	return _route.is_empty()


## Abandona el horario y va a `zone_id`/`tile` (p. ej. Helene vuelve a la consulta cuando decide no subir).
func redirect(zone_id: String, tile: Vector2i) -> void:
	var now: int = TimeManager.now_minutes()
	_entries = [{"minutes": now, "depart": now, "boards": false, "no_snap": true, "zone": zone_id, "tile": tile, "via": [] as Array[Vector2i]}]
	_entry_index = -1
	_on_minute_changed(0, 0)


func _plan_route(entry: Dictionary) -> void:
	_route.clear()
	var dest_zone: String = entry["zone"]
	if dest_zone == ZoneManager.GONE and entry.get("boards", false):
		_route.append({"instant": true, "zone": ZoneManager.GONE})   # sube al tren, que tiene al lado
		return
	if dest_zone == ZoneManager.GONE:
		# Se va caminando hasta la salida más cercana y recién ahí desaparece: si se lo demoró con una charla,
		# no se esfuma en medio de la plaza. Sale por un borde (se va del pueblo), no por una puerta: si entrara a
		# una casa, el jugador lo seguiría y no lo encontraría adentro. Desde un interior, primero sale a la calle.
		var here_zone: String = zone
		var here_px: Vector2 = position
		var street: String = _street_of(zone)
		if street != "" and street != zone:
			var exit_at: Vector2i = ZoneManager.exit_cell(zone, street)
			var arrive: Variant = ZoneManager.spawn_px(street, zone)
			if exit_at.x >= 0 and arrive != null:
				_append_path(zone, position, ZoneManager.tile_px(exit_at))
				_route.append({"instant": true, "zone": street, "pos": arrive})
				here_zone = street
				here_px = arrive
		var out: Variant = _nearest_exit_px(here_zone, here_px)
		if out != null:
			_append_path(here_zone, here_px, out)
		_route.append({"instant": true, "zone": ZoneManager.GONE})
		return
	if zone == ZoneManager.GONE or zone == "":
		# Vuelve de afuera: aparece en un borde (o en la puerta, si es un interior) y camina hasta su lugar.
		var door: Vector2 = _entrance_px(dest_zone, ZoneManager.tile_px(entry["tile"]))
		_route.append({"instant": true, "zone": dest_zone, "pos": door})
		var from_px: Vector2 = door
		for via: Vector2i in entry["via"]:
			_append_path(dest_zone, from_px, ZoneManager.tile_px(via))
			from_px = ZoneManager.tile_px(via)
		_append_path(dest_zone, from_px, ZoneManager.tile_px(entry["tile"]))
		return
	var here_zone: String = zone
	var here_px: Vector2 = position
	# Zonas intermedias: por cada salto, camina hasta la salida y reaparece del otro lado.
	var hops: Array[String] = ZoneManager.zone_path(zone, dest_zone)
	for i in range(1, hops.size()):
		var next_zone: String = hops[i]
		var exit_at: Vector2i = ZoneManager.exit_cell(here_zone, next_zone)
		var arrive: Variant = ZoneManager.spawn_px(next_zone, here_zone)
		if exit_at.x < 0 or arrive == null:
			_route.append({"instant": true, "zone": next_zone, "pos": ZoneManager.tile_px(entry["tile"])})
			here_zone = next_zone
			here_px = ZoneManager.tile_px(entry["tile"])
			continue
		var exit_px: Vector2 = ZoneManager.tile_px(exit_at)
		_append_path(here_zone, here_px, exit_px)
		_route.append({"instant": true, "zone": next_zone, "pos": arrive})
		here_zone = next_zone
		here_px = arrive
	if hops.is_empty() and dest_zone != zone:
		_route.append({"instant": true, "zone": dest_zone, "pos": ZoneManager.tile_px(entry["tile"])})
		return
	for via: Vector2i in entry["via"]:
		var via_px: Vector2 = ZoneManager.tile_px(via)
		_append_path(here_zone, here_px, via_px)
		here_px = via_px
	_append_path(here_zone, here_px, ZoneManager.tile_px(entry["tile"]))


## Salida más cercana a `from` en `zone_id`: un borde si la zona tiene, si no una puerta (interiores).
## null si no hay ninguna.
func _nearest_exit_px(zone_id: String, from: Vector2) -> Variant:
	if zone_id == "" or zone_id == ZoneManager.GONE:
		return null
	var best: Variant = null
	var edges_only: bool = ZoneManager.is_exterior(zone_id)
	for target: String in ZoneManager.neighbors(zone_id):
		if edges_only and ZoneManager.connection(zone_id, target).get("kind", "door") != "edge":
			continue
		var cell: Vector2i = ZoneManager.exit_cell(zone_id, target)
		if cell.x < 0:
			continue
		var px: Vector2 = ZoneManager.tile_px(cell)
		if best == null or from.distance_to(px) < from.distance_to(best):
			best = px
	return best


## Exterior al que da la puerta de un interior ("" si es exterior o no da a la calle). Sigue puertas internas
## (la cripta da a la sacristía, que da a la nave, que da al centro).
func _street_of(zone_id: String) -> String:
	if ZoneManager.is_exterior(zone_id):
		return zone_id
	var seen: Array[String] = [zone_id]
	var frontier: Array[String] = [zone_id]
	while not frontier.is_empty():
		var z: String = frontier.pop_front()
		for n: String in ZoneManager.neighbors(z):
			if n in seen:
				continue
			if ZoneManager.is_exterior(n):
				return ZoneManager.zone_path(zone_id, n)[1] if ZoneManager.zone_path(zone_id, n).size() > 1 else n
			seen.append(n)
			frontier.append(n)
	return ""


## Por dónde entra a `zone_id` quien llega de afuera: el borde más cercano a su destino en un exterior, o la
## puerta (lado de adentro) en un interior.
func _entrance_px(zone_id: String, to: Vector2) -> Vector2:
	if ZoneManager.is_exterior(zone_id):
		var edge: Variant = _nearest_exit_px(zone_id, to)
		return edge if edge != null else to
	for n: String in ZoneManager.neighbors(zone_id):
		var cell: Vector2i = ZoneManager.exit_cell(zone_id, n)
		if cell.x >= 0 and ZoneManager.is_exterior(n):
			return ZoneManager.tile_px(cell)
	for n: String in ZoneManager.neighbors(zone_id):
		var cell2: Vector2i = ZoneManager.exit_cell(zone_id, n)
		if cell2.x >= 0:
			return ZoneManager.tile_px(cell2)
	return to


## Nombre sobre la cabeza: aparece solo al pasar el mouse por encima del NPC (o para todos con N, ayuda de depuración
## que no se guarda). Va en un recuadro negro con borde marrón y letra blanca, distinto de lo que dicen (globos y
## frases), para que no se confunda con un diálogo ni ensucie la pantalla.
func _add_name_tag() -> void:
	_name_tag = PanelContainer.new()
	_name_tag.add_theme_stylebox_override("panel", UiStyle.name_tag())
	_name_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_tag.z_index = TEXT_Z
	_name_tag.visible = false
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 10)
	_name_label.add_theme_color_override("font_color", UiStyle.NAME_TEXT)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_tag.add_child(_name_label)
	add_child(_name_tag)
	refresh_name_tag()


func _set_name_text(text: String) -> void:
	if _name_label.text == text:
		return
	_name_label.text = text
	_name_tag.reset_size()
	_name_tag.position.x = -roundf(_name_tag.get_combined_minimum_size().x / 2.0)   # centrado sobre la cabeza
	lift_name_tag(_name_rows)


## Ancho del recuadro del nombre en px (para que ChatterSystem separe los que se pisan).
func name_tag_width() -> float:
	if _name_tag == null or not _name_tag.visible:
		return 0.0
	return _name_tag.get_combined_minimum_size().x


## Sube el nombre `rows` renglones (0 = en su lugar).
func lift_name_tag(rows: int) -> void:
	_name_rows = rows
	if _name_tag != null:
		_name_tag.position.y = NAME_TAG_Y + _text_drop - rows * NAME_TAG_ROW


func refresh_name_tag() -> void:
	if _name_tag != null:
		_all_names = bool(SettingsManager.get_value("debug_name_tags"))
		_set_name_text(_display_name())


func _mouse_over() -> bool:
	return visible and Rect2(global_position + Vector2(-9, -34), Vector2(18, 34)).has_point(get_global_mouse_position())


## Cómo lo nombra el jugador ahora (la descripción hasta que sepa cómo se llama).
func display_name() -> String:
	return _display_name()


func _display_name() -> String:
	var who: String = JournalManager.person_for_dialogue(npc_id)
	if who != "":
		return JournalManager.display_name(who)   # "El del abrigo gris" hasta que sepa cómo se llama
	for key: String in ["chr_" + npc_id, "pax_" + npc_id]:
		var text: String = tr(key)
		if text != key:
			return text
	return npc_id.capitalize()


## Agrega los puntos de paso para ir de `a` a `b` dentro de `zone_id`, rodeando obstáculos.
func _append_path(zone_id: String, a: Vector2, b: Vector2) -> void:
	for waypoint in ZoneManager.find_path(zone_id, a, b):
		_route.append({"pos": waypoint})


func _on_zone_changed(_zone_id: String) -> void:
	_refresh_presence()


## Solo está "en el mundo" (visible, con colisión e interacción) en la zona del jugador.
func _refresh_presence() -> void:
	var present: bool = zone == ZoneManager.current_zone
	visible = present
	collision_layer = 2 if present else 0
	_area.set_deferred("monitoring", present and interactive)
	if not present:
		_prompt.set_active(false)
		if ZoneManager.player != null:
			ZoneManager.player.clear_interactable(self)


func set_highlight(on: bool) -> void:
	_prompt.set_active(on)


func _on_body_entered(body: Node2D) -> void:
	if interactive and body is PlayerController:
		(body as PlayerController).set_interactable(self)


func _on_body_exited(body: Node2D) -> void:
	if body is PlayerController:
		(body as PlayerController).clear_interactable(self)
