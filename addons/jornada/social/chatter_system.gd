extends Node
## Barullo del pueblo (data/barks.json, generado por tools/gen_barks.py):
##   · frases sueltas: cada NPC de la zona del jugador dice algo de tanto en tanto
##   · charlas: cuando dos se cruzan, uno habla y el otro contesta (pares propios o de vecinos en general)
##   · brush_off: al hablarle a alguien que no tiene diálogo ahora, contesta con una frase corta
##   · llamados ("calls"): un NPC le habla al jugador desde lejos al acercarse a un lugar, y puede dar flags
##     (el encargo de las velas de Simeon). Cada uno sale una vez por loop. Campos opcionales:
##       time_min / time_max   ventana horaria ("HH:MM")
##       dialogue: true        en vez de una frase, abre el diálogo del NPC (la entrada que corresponda por sus condiciones)
##       npc_zone              el NPC tiene que estar en esa zona (aunque no sea la del jugador): la voz llega "a través
##                             de la puerta", sin que se lo vea; el sonido (sfx) suena antes
##       sfx                   sonido que acompaña al llamado (p. ej. golpes en la puerta)
## De cerca la frase se ve entera; de lejos, medio transparente (alpha_for). No da flags ni sospecha.

const PATH: String = "res://data/barks.json"
## Opacidad según la distancia al jugador (px): entera hasta NEAR, FAR_ALPHA desde FAR.
const NEAR: float = 96.0
const FAR: float = 280.0
const FAR_ALPHA: float = 0.35
## Cada NPC habla solo cada SOLO_MIN..SOLO_MAX segundos (reales; F los acelera como a todo).
const SOLO_MIN: float = 10.0
const SOLO_MAX: float = 26.0
## Dos NPCs "se cruzan" a menos de esta distancia; un mismo par no vuelve a charlar antes de PAIR_COOLDOWN.
const PAIR_RANGE: Vector2 = Vector2(48.0, 30.0)
const PAIR_COOLDOWN: float = 75.0
const REPLY_DELAY: float = 2.4
## Para que no hablen todos a la vez.
const MAX_AT_ONCE: int = 3
const MIN_GAP: float = 1.2
const TICK: float = 0.5

var _data: Dictionary = {}
var _clock: float = 0.0
var _tick_left: float = 0.0
var _last_start: float = -100.0
var _next_solo: Dictionary = {}      # npc_id -> _clock en que puede volver a hablar solo
var _pair_ready: Dictionary = {}     # "a|b" -> _clock en que ese par puede volver a charlar
var _last_key: Dictionary = {}       # npc_id -> última frase dicha (para no repetirla)
var _calls_done: Dictionary = {}     # id del llamado -> true (se vacía cada loop)


func _ready() -> void:
	_data = GameConfig.read_data(PATH)
	ZoneManager.zone_changed.connect(func(_z: String) -> void: _next_solo.clear())
	LoopManager.loop_started.connect(func(_n: int) -> void: _calls_done.clear())


func _process(delta: float) -> void:
	if get_tree().paused or DialogueManager.is_active or ZoneManager.player == null:
		return
	_clock += delta
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = TICK
	_tick()


## Opacidad de una frase dicha en `pos` según lo lejos que esté el jugador.
func alpha_for(pos: Vector2) -> float:
	var player: PlayerController = ZoneManager.player
	if player == null:
		return 1.0
	var t: float = clampf((pos.distance_to(player.global_position) - NEAR) / (FAR - NEAR), 0.0, 1.0)
	return lerpf(1.0, FAR_ALPHA, t)


## "No tengo nada que decirle": propia del NPC si tiene, si no según sea hombre, mujer o chico.
func brush_off(actor: NpcActor) -> void:
	var keys: Array = _data.get("brush_npc", {}).get(actor.npc_id, [])
	if keys.is_empty():
		keys = _data.get("brush", {}).get(_data.get("kind", {}).get(actor.npc_id, "male"), [])
	if keys.is_empty():
		return
	actor.show_bark(tr(_pick_key(actor.npc_id, keys.map(func(k: String) -> Dictionary: return {"key": k}))), UiStyle.ACCENT, 2.0)


func _tick() -> void:
	var present: Array[NpcActor] = []
	var busy: int = 0
	for node in get_tree().get_nodes_in_group("npc_actors"):
		var actor := node as NpcActor
		if actor == null or not actor.visible or actor.zone != ZoneManager.current_zone:
			continue
		if actor.is_barking():
			busy += 1
		elif not actor.is_talking():
			present.append(actor)
	_separate_name_tags()
	_check_calls()
	if busy >= MAX_AT_ONCE or _clock - _last_start < MIN_GAP:
		return
	if _try_pair(present):
		return
	present.shuffle()
	for actor: NpcActor in present:
		if not _next_solo.has(actor.npc_id):
			_next_solo[actor.npc_id] = _clock + randf_range(2.0, SOLO_MAX)   # al entrar a la zona no hablan todos juntos
			continue
		if _clock < _next_solo[actor.npc_id]:
			continue
		_next_solo[actor.npc_id] = _clock + randf_range(SOLO_MIN, SOLO_MAX)
		var lines: Array = _available(_data.get("solo", {}).get(actor.npc_id, []))
		if lines.is_empty():
			continue
		_say(actor, _pick_key(actor.npc_id, lines))
		return


## Llamados: si el jugador está cerca del lugar y el NPC en la zona (y se cumplen los flags), el NPC le habla.
func _check_calls() -> void:
	var player: PlayerController = ZoneManager.player
	for call: Dictionary in _data.get("calls", []):
		if _calls_done.has(call["id"]) or call["zone"] != ZoneManager.current_zone:
			continue
		var spot: Vector2 = ZoneManager.tile_px(Vector2i(call["tile"][0], call["tile"][1]))
		if player.global_position.distance_to(spot) > float(call.get("radius", 64)):
			continue
		if not _call_time_ok(call):
			continue
		if not call.get("knowledge", []).all(func(f: String) -> bool: return LoopManager.has_knowledge(f)):
			continue
		if call.get("not_knowledge", []).any(func(f: String) -> bool: return LoopManager.has_knowledge(f)):
			continue
		var actor: NpcActor = _caller(call)
		if actor == null or actor.is_talking():
			continue
		if call.get("dialogue", false):
			if DialogueManager.is_active:
				continue   # se reintenta cuando termine la charla en curso
			_calls_done[call["id"]] = true
			_open_dialogue(call)
			continue
		_calls_done[call["id"]] = true
		actor.show_bark(tr(call["key"]), UiStyle.ACCENT, 4.0)
		for flag: String in call.get("reveals", []):
			LoopManager.gain_knowledge(flag)


func _call_time_ok(call: Dictionary) -> bool:
	var now: int = TimeManager.now_minutes()
	if call.has("time_min") and now < TimeManager.parse_clock(call["time_min"]):
		return false
	return not (call.has("time_max") and now > TimeManager.parse_clock(call["time_max"]))


## Quien llama: en la zona del jugador y a la vista; o, con `npc_zone`, en esa otra zona (se lo oye, no se lo ve).
func _caller(call: Dictionary) -> NpcActor:
	var wanted_zone: String = call.get("npc_zone", ZoneManager.current_zone)
	for node in get_tree().get_nodes_in_group("npc_actors"):
		if node is NpcActor and node.npc_id == call["npc"] and node.zone == wanted_zone \
				and (node.visible or wanted_zone != ZoneManager.current_zone):
			return node
	return null


## Llamado que abre una charla: da los flags (que eligen la entrada del diálogo), suena el sonido y habla.
func _open_dialogue(call: Dictionary) -> void:
	for flag: String in call.get("reveals", []):
		LoopManager.gain_knowledge(flag)
	if call.has("sfx"):
		AudioManager.play_sfx(call["sfx"], -2.0)
		await get_tree().create_timer(1.2, false).timeout   # lo que tarda en abrir/contestar quien está del otro lado
	if not DialogueManager.is_active:
		DialogueManager.start(call["npc"])


## Si dos nombres se pisan, el del que está más al norte sube un renglón (o dos, si hay tres juntos).
func _separate_name_tags() -> void:
	var actors: Array = get_tree().get_nodes_in_group("npc_actors").filter(func(n: Node) -> bool:
		return n is NpcActor and n.visible and n.zone == ZoneManager.current_zone)
	actors.sort_custom(func(a: NpcActor, b: NpcActor) -> bool: return a.global_position.y > b.global_position.y)
	var placed: Array = []    # [centro x, y del renglón, medio ancho]
	for actor: NpcActor in actors:
		var half: float = actor.name_tag_width() * 0.5 + 3.0
		var rows: int = 0
		var x: float = actor.global_position.x
		while rows < 3 and placed.any(func(p: Array) -> bool:
				return absf(p[0] - x) < p[2] + half and absf(p[1] - (actor.global_position.y - rows * NpcActor.NAME_TAG_ROW)) < NpcActor.NAME_TAG_ROW):
			rows += 1
		actor.lift_name_tag(rows)
		placed.append([x, actor.global_position.y - rows * NpcActor.NAME_TAG_ROW, half])


## Busca dos NPCs cerca uno del otro con algo que decirse; si los hay, arranca la charla.
func _try_pair(present: Array[NpcActor]) -> bool:
	for i in present.size():
		for j in range(i + 1, present.size()):
			var a: NpcActor = present[i]
			var b: NpcActor = present[j]
			if a.npc_id == b.npc_id:
				continue
			var offset: Vector2 = (a.global_position - b.global_position).abs()
			if offset.x > PAIR_RANGE.x or offset.y > PAIR_RANGE.y:
				continue
			var pair_id: String = "%s|%s" % [a.npc_id, b.npc_id] if a.npc_id < b.npc_id else "%s|%s" % [b.npc_id, a.npc_id]
			if _clock < _pair_ready.get(pair_id, 0.0):
				continue
			var exchange: Array = _exchange_for(a, b)
			if exchange.is_empty():
				continue
			_pair_ready[pair_id] = _clock + PAIR_COOLDOWN
			var line: Dictionary = exchange[1].pick_random()
			_say(exchange[0], line["a"]["key"])
			_reply(exchange[2], line["b"]["key"])
			return true
	return false


## [primero, líneas, segundo] para el par (en el orden en que está escrito), o [] si no tienen nada que decirse.
func _exchange_for(a: NpcActor, b: NpcActor) -> Array:
	var pairs: Dictionary = _data.get("pairs", {})
	for order: Array in [[a, b], [b, a]]:
		var lines: Array = _available_pairs(pairs.get("%s|%s" % [order[0].npc_id, order[1].npc_id], []))
		if not lines.is_empty():
			return [order[0], lines, order[1]]
	var generic: Dictionary = _data.get("generic", {})
	var members: Array = generic.get("members", [])
	if a.npc_id in members and b.npc_id in members:
		var lines: Array = _available_pairs(generic.get("lines", []))
		if not lines.is_empty():
			return [a, lines, b]
	return []


func _reply(actor: NpcActor, key: String) -> void:
	await get_tree().create_timer(REPLY_DELAY, false).timeout
	if is_instance_valid(actor) and actor.visible and not actor.is_talking():
		_say(actor, key)


func _say(actor: NpcActor, key: String) -> void:
	_last_start = _clock
	_last_key[actor.npc_id] = key
	var text: String = tr(key)
	actor.show_bark(text, UiStyle.TEXT, clampf(1.4 + text.length() * 0.045, 2.0, 4.5))


## Elige una frase al azar sin repetir la última que dijo ese NPC.
func _pick_key(npc_id: String, lines: Array) -> String:
	var options: Array = lines.filter(func(l: Dictionary) -> bool: return l["key"] != _last_key.get(npc_id, ""))
	if options.is_empty():
		options = lines
	var key: String = options.pick_random()["key"]
	_last_key[npc_id] = key
	return key


func _available(lines: Array) -> Array:
	return lines.filter(_in_window)


func _available_pairs(lines: Array) -> Array:
	return lines.filter(func(l: Dictionary) -> bool: return _in_window(l["a"]) and _in_window(l["b"]))


func _in_window(line: Dictionary) -> bool:
	if not line.has("from"):
		return true
	var now: int = TimeManager.now_minutes()
	return now >= TimeManager.parse_clock(line["from"]) and now <= TimeManager.parse_clock(line["to"])
