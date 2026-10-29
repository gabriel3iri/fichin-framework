extends Node
## Alguien que le habla a una sala (un cura en misa, un maestro en clase) y asientos para escucharlo
## (data/speeches.json; sin el archivo no hace nada).
##
## - seats: por objeto (el nombre del PNG del prop), los puestos donde sentarse (offsets en px desde el pie del objeto)
##   y hacia dónde se mira sentado. Al entrar a una zona se pone un Seat en cada puesto.
## - speeches: quién habla (npc), dónde (zone), entre qué horas (time_min/time_max, opcionales), qué dice (lines, claves
##   del CSV, en orden y en ronda) y cada cuántos segundos reales (every). Si el jugador lo escucha sentado
##   listen_minutes minutos del juego, gana `reveals` y quien habla se acerca a él y abre su diálogo (la entrada que
##   elija su propio JSON con esos flags). Habla solo mientras el jugador está en la zona: si no, nadie lo oye.
## - service: quien atiende en una zona (el tabernero). Cuando el jugador se sienta, viene y abre su diálogo: a un
##   asiento de la barra (que no mira a una mesa) llega por detrás del mostrador (`counter_offset`, en celdas desde el asiento);
##   a una mesa, camina hasta el jugador. Después no vuelve solo hasta pasados `again_minutes` (60 por defecto) en esa
##   zona; sentado, E lo llama (Seat.call_service).

const PATH: String = "res://data/speeches.json"
## A cuánto del jugador se detiene a hablarle y cuánto espera como mucho a llegar (s reales).
const TALK_RANGE: float = 30.0
const APPROACH_SECONDS: float = 12.0

var _seats: Dictionary = {}
var _speeches: Array = []
var _service: Array = []
var _serving: bool = false
var _line_index: Dictionary = {}       # npc -> próxima línea
var _line_wait: Dictionary = {}        # npc -> segundos hasta la próxima línea
var _listened: Dictionary = {}         # npc -> minutos escuchados sentado (esta jornada)
var _approaching: bool = false
var _served_at: Dictionary = {}        # zona -> minuto en que lo atendieron (esta jornada)
var _generation: int = 0


func _ready() -> void:
	var cfg: Dictionary = GameConfig.read_data(PATH)
	_seats = cfg.get("seats", {})
	_speeches = cfg.get("speeches", [])
	_service = cfg.get("service", [])
	if cfg.is_empty():
		set_process(false)
		return
	ZoneManager.zone_changed.connect(_on_zone_changed)
	TimeManager.minute_changed.connect(_on_minute)
	LoopManager.loop_started.connect(func(_n: int) -> void: _reset())
	LoopManager.game_reset.connect(_reset)


func _reset() -> void:
	_listened.clear()
	_served_at.clear()
	_line_index.clear()
	_line_wait.clear()
	_approaching = false
	_serving = false
	_generation += 1


func _process(delta: float) -> void:
	for speech: Dictionary in _speeches:
		var actor: NpcActor = _speaker(speech)
		if actor == null or actor.is_talking() or actor.is_on_detour():
			continue
		var npc: String = speech["npc"]
		_line_wait[npc] = float(_line_wait.get(npc, 0.0)) - delta
		if float(_line_wait[npc]) > 0.0 or actor.is_barking():
			continue
		var lines: Array = speech.get("lines", [])
		if lines.is_empty():
			continue
		var idx: int = int(_line_index.get(npc, 0)) % lines.size()
		_line_index[npc] = idx + 1
		var text: String = tr(String(lines[idx]))
		actor.show_bark(text, UiStyle.TEXT, clampf(1.6 + text.length() * 0.05, 2.5, 6.0), &"address")   # globo de discurso
		_line_wait[npc] = float(speech.get("every", 6.0))


## Quien da este discurso, si ahora está hablando a la sala donde está el jugador.
func _speaker(speech: Dictionary) -> NpcActor:
	if ZoneManager.current_zone != String(speech.get("zone", "")) or not _time_ok(speech):
		return null
	for node in get_tree().get_nodes_in_group("npc_actors"):
		if node is NpcActor and node.npc_id == speech["npc"] and node.zone == ZoneManager.current_zone and node.visible:
			return node
	return null


func _time_ok(speech: Dictionary) -> bool:
	var now: int = TimeManager.now_minutes()
	if speech.has("time_min") and now < TimeManager.parse_clock(speech["time_min"]):
		return false
	return not speech.has("time_max") or now <= TimeManager.parse_clock(speech["time_max"])


## Un minuto del juego sentado escuchando suma; al llegar a listen_minutes, quien habla viene a buscarlo.
func _on_minute(_hour: int, _minute: int) -> void:
	var player: PlayerController = ZoneManager.player
	if player == null or not player.seated or _approaching or DialogueManager.is_active:
		return
	for speech: Dictionary in _speeches:
		var actor: NpcActor = _speaker(speech)
		if actor == null or actor.is_talking() or actor.is_on_detour():
			continue
		var reveals: Array = speech.get("reveals", [])
		if not reveals.is_empty() and reveals.all(func(f: String) -> bool: return LoopManager.has_knowledge(f)):
			continue   # ya lo escuchó hoy
		var npc: String = speech["npc"]
		_listened[npc] = int(_listened.get(npc, 0)) + 1
		if int(_listened[npc]) >= int(speech.get("listen_minutes", 5)):
			for flag: String in reveals:
				LoopManager.gain_knowledge(flag)
			_approach(actor)
			return


## Camina hasta el jugador sentado (sin aparecer a su lado), le habla y después vuelve a lo suyo.
func _approach(actor: NpcActor) -> void:
	_approaching = true
	var generation: int = _generation
	actor.approach_player()
	var waited: float = 0.0
	while waited < APPROACH_SECONDS:
		await get_tree().process_frame
		if generation != _generation or not is_instance_valid(actor) or not is_instance_valid(ZoneManager.player):
			return
		waited += get_process_delta_time()
		if actor.global_position.distance_to(ZoneManager.player.global_position) <= TALK_RANGE:
			break
	_approaching = false
	if DialogueManager.is_active or not DialogueManager.start(actor.npc_id):
		actor.end_detour()
		return
	var npc_id: String = actor.npc_id
	await _dialogue_end(npc_id, generation)
	if is_instance_valid(actor):
		actor.end_detour()


## El jugador se sentó: si en esta zona alguien atiende y está libre, viene a tomarle el pedido. Si ya lo atendió hace
## poco, no vuelve solo (`called`: lo llamó el jugador, sentado, con E).
func serve(seat: Seat, called: bool = false) -> void:
	if _serving or DialogueManager.is_active:
		return
	for svc: Dictionary in _service:
		if String(svc.get("zone", "")) != ZoneManager.current_zone:
			continue
		var last: int = int(_served_at.get(ZoneManager.current_zone, -100000))
		if not called and TimeManager.now_minutes() - last < int(svc.get("again_minutes", 60)):
			return
		var actor: NpcActor = null
		for node in get_tree().get_nodes_in_group("npc_actors"):
			if node is NpcActor and node.npc_id == svc["npc"] and node.zone == ZoneManager.current_zone and node.visible:
				actor = node
		if actor == null or actor.is_talking() or actor.is_on_detour():
			return
		_serving = true
		var generation: int = _generation
		var offset: Array = svc.get("counter_offset", [0, -2])
		var cell: Vector2i = ZoneManager.cell_of(seat.position - Vector2(0.0, 1.0)) + Vector2i(int(offset[0]), int(offset[1]))
		var at: Vector2 = ZoneManager.tile_px(cell)
		if seat.at_table or ZoneManager.is_cell_solid(ZoneManager.current_zone, cell):
			actor.approach_player()
			at = ZoneManager.player.global_position
		else:
			actor.begin_detour(ZoneManager.current_zone, at)
		var waited: float = 0.0
		while waited < APPROACH_SECONDS:
			await get_tree().process_frame
			if generation != _generation or not is_instance_valid(actor) or not is_instance_valid(ZoneManager.player):
				return
			waited += get_process_delta_time()
			if actor.global_position.distance_to(at) <= (TALK_RANGE if seat.at_table else 2.0):
				break
		_serving = false
		var player: PlayerController = ZoneManager.player
		if not player.seated or DialogueManager.is_active or not DialogueManager.start(actor.npc_id):
			actor.end_detour()   # se levantó mientras venía: vuelve a lo suyo
			return
		_served_at[ZoneManager.current_zone] = TimeManager.now_minutes()
		await _dialogue_end(actor.npc_id, generation)
		if is_instance_valid(actor):
			actor.end_detour()
		return


func _dialogue_end(npc_id: String, generation: int) -> void:
	while generation == _generation:
		var ended: String = await DialogueManager.dialogue_ended
		if ended == npc_id:
			return


func _on_zone_changed(_zone_id: String) -> void:
	var root: Node = ZoneManager.zone_root
	if root == null:
		return
	var seats: Array[Seat] = []
	var props: Array[Node] = root.find_children("*", "Prop", true, false)
	for prop: Node in props:
		var kind: String = _kind(prop)
		if not _seats.has(kind):
			continue
		var cfg: Dictionary = _seats[kind]
		for offset: Array in cfg.get("spots", [[0, 0]]):
			var seat := Seat.new()
			seat.position = (prop as Node2D).position + Vector2(float(offset[0]), float(offset[1]))
			seat.face = _face(String(cfg.get("face", "up")))
			seat.at_table = false
			# "toward": mira hacia la mesa más cercana de esas (si hay una a menos de toward_range px)
			var best: float = float(cfg.get("toward_range", 40.0))
			for other: Node in props:
				if _kind(other) in (cfg.get("toward", []) as Array):
					var offset_to: Vector2 = (other as Node2D).position - (prop as Node2D).position   # del mueble, no del puesto
					if offset_to.length() < best:
						best = offset_to.length()
						seat.face = Vector2(signf(offset_to.x), 0.0) if absf(offset_to.x) > absf(offset_to.y) else Vector2(0.0, signf(offset_to.y))
						seat.at_table = true
			seats.append(seat)
	for seat in seats:
		root.add_child(seat)


static func _kind(prop: Node) -> String:
	var texture: Texture2D = (prop as Prop).prop_texture
	return texture.resource_path.get_file().get_basename() if texture != null else ""


static func _face(name: String) -> Vector2:
	match name:
		"down": return Vector2.DOWN
		"left": return Vector2.LEFT
		"right": return Vector2.RIGHT
	return Vector2.UP
