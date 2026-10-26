extends Node
## Avistamientos: quién vio al jugador, dónde y cuándo. Cada minuto de juego se anota en qué zona está el jugador y qué
## personajes lo tienen a la vista (los de su misma zona; al aire libre, a menos de SIGHT_RANGE px). Guarda la última hora y
## media y se vacía al empezar la jornada.
## Lo usa SearchSystem para que quien busca al jugador llegue adonde alguien pudo haberlo visto, y lo diga. Es lo que ven
## DEL jugador; WitnessManager anota lo que el jugador ve.

const KEEP_MINUTES: int = 90
const SIGHT_RANGE: float = 200.0

var _log: Array = []   # {minute, zone, pos, witnesses: Array[String], to?: String}
var _last_zone: String = ""
var _last_pos: Vector2 = Vector2.ZERO
var _loaded: Array = []   # lo leído del guardado; se aplica cuando la carga rápida termina (antes el loop lo vacía)


func _ready() -> void:
	TimeManager.minute_changed.connect(_on_minute_changed)
	ZoneManager.zone_changed.connect(_on_zone_changed)
	LoopManager.loop_started.connect(func(_n: int) -> void: clear())
	LoopManager.game_reset.connect(clear)
	SaveManager.register_section("sightings", _to_json, func(value: Variant) -> void: _loaded = value if typeof(value) == TYPE_ARRAY else [])
	SaveManager.quick_state_applied.connect(_on_quick_state_applied)


## Al cambiar de zona, quienes lo tenían a la vista en la que dejó lo vieron irse hacia la nueva («lo vio subir a su cuarto»).
## En este momento el jugador todavía está donde estaba: ZoneManager lo mueve después de avisar.
func _on_zone_changed(zone_id: String) -> void:
	var player: PlayerController = ZoneManager.player
	if _last_zone != "" and _last_zone != zone_id and player != null and is_instance_valid(player):
		var witnesses: Array[String] = _witnesses(_last_zone, player.global_position)
		if not witnesses.is_empty():
			_log.append({"minute": TimeManager.now_minutes(), "zone": _last_zone, "pos": player.global_position,
					"witnesses": witnesses, "to": zone_id})
	_last_zone = zone_id
	if player != null and is_instance_valid(player):
		_last_pos = player.global_position


func _on_minute_changed(_hour: int, _minute: int) -> void:
	record()


## Anota ahora mismo qué zona pisa el jugador y quién lo ve.
func record() -> void:
	var player: PlayerController = ZoneManager.player
	if player == null or not is_instance_valid(player) or ZoneManager.current_zone == "":
		return
	var zone: String = ZoneManager.current_zone
	var now: int = TimeManager.now_minutes()
	if not _log.is_empty() and int(_log[-1]["minute"]) == now and _log[-1]["zone"] == zone and not _log[-1].has("to"):
		return   # ya anotado en este minuto (p. ej. al cargar una partida guardada en este mismo lugar)
	_log.append({"minute": now, "zone": zone, "pos": player.global_position, "witnesses": _witnesses(zone, player.global_position)})
	while not _log.is_empty() and now - int(_log[0]["minute"]) > KEEP_MINUTES:
		_log.pop_front()


## Quiénes están en `zone` y ven a alguien parado en `at` (al aire libre, a menos de SIGHT_RANGE px).
func _witnesses(zone: String, at: Vector2) -> Array[String]:
	var out: Array[String] = []
	for node in get_tree().get_nodes_in_group("npc_actors"):
		var actor := node as NpcActor
		if actor == null or actor.zone != zone:
			continue
		if ZoneManager.is_exterior(zone) and actor.global_position.distance_to(at) > SIGHT_RANGE:
			continue
		out.append(actor.npc_id)
	return out


## Avistamientos de los últimos `window` minutos, del más nuevo al más viejo. `exclude`: quién no cuenta como testigo
## (p. ej. quien está buscando). Solo los que tuvieron algún testigo; cada uno trae `witnesses` ya filtrados.
func recent(window: int, exclude: Array = []) -> Array:
	var now: int = TimeManager.now_minutes()
	var out: Array = []
	for i in range(_log.size() - 1, -1, -1):
		var entry: Dictionary = _log[i]
		if now - int(entry["minute"]) > window:
			break
		var seen: Array = (entry["witnesses"] as Array).filter(func(id: String) -> bool: return not id in exclude)
		if not seen.is_empty():
			var copy: Dictionary = entry.duplicate()
			copy["witnesses"] = seen
			out.append(copy)
	return out


func _to_json() -> Array:
	var out: Array = []
	for entry: Dictionary in _log:
		var item: Dictionary = entry.duplicate()
		var pos: Vector2 = entry["pos"]
		item["pos"] = [pos.x, pos.y]
		out.append(item)
	return out


func _on_quick_state_applied() -> void:
	_log.clear()
	for item: Variant in _loaded:
		if typeof(item) != TYPE_DICTIONARY or not item.has("pos"):
			continue
		var entry: Dictionary = (item as Dictionary).duplicate()
		entry["pos"] = Vector2(float(item["pos"][0]), float(item["pos"][1]))
		entry["minute"] = int(item.get("minute", 0))
		entry["witnesses"] = (item.get("witnesses", []) as Array).map(func(id: Variant) -> String: return str(id))
		_log.append(entry)
	_loaded = []


func clear() -> void:
	_log.clear()
	_last_zone = ""
