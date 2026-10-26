extends Node
## Fastidio: el jugador puede molestar a un NPC (propuesta de diseño; no está en el canon, ver docs/planning).
##
## Qué suma (por NPC, por loop):
##   · cerrarle el paso mientras camina (el NPC se detiene y espera, ver NpcActor)
##   · rondarlo sin hablarle (a menos de 30 px durante 8 s)
##   · volver a hablarle de inmediato (antes de 4 s de terminar una conversación)
## Cómo reacciona (data/annoyance.json):
##   1 punto  → su gesto propio (canon 08 §3: Franz se muerde el labio, Klara se acomoda el lápiz...)
##   2 puntos → una frase corta sobre la cabeza
##   3 puntos → "salta": se gana el flag <npc>_annoyed, el NPC se vuelve y empieza su entrada <npc>_snap
## El fastidio baja solo (1 punto cada 25 s sin molestarlo) y se reinicia cada loop. Un NPC solo salta una vez por loop.
## Principios: nunca bloquea el camino crítico (todo lo que da también se consigue hablando), el NPC nunca se
## retrasa más de unos minutos (ver NpcActor), y lo que se paga es sospecha o confianza, no tiempo.

const PATH: String = "res://data/annoyance.json"
const LINGER_RANGE: Vector2 = Vector2(30.0, 22.0)
const LINGER_SECONDS: float = 8.0
const PESTER_SECONDS: float = 4.0
const DECAY_SECONDS: float = 25.0
## El NPC que salta empieza a hablar solo si el jugador lo tiene cerca y a la vista.
const SNAP_REACH: Vector2 = Vector2(260.0, 160.0)

var _cfg: Dictionary = {}
var _ticks_to_snap: int = 3
var _ticks: Dictionary = {}
var _quiet: Dictionary = {}
var _linger: Dictionary = {}
var _last_talk_end: Dictionary = {}
var _pending: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var parsed: Dictionary = GameConfig.read_data(PATH)
	_cfg = parsed.get("npcs", {})
	_ticks_to_snap = int(parsed.get("ticks_to_snap", 3))
	LoopManager.loop_started.connect(func(_n: int) -> void: reset())
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)


func config() -> Dictionary:
	return _cfg


func reset() -> void:
	_ticks.clear()
	_quiet.clear()
	_linger.clear()
	_last_talk_end.clear()
	_pending.clear()


func ticks_of(npc_id: String) -> int:
	return int(_ticks.get(npc_id, 0))


## Un punto de fastidio para `npc_id`. `reason` solo sirve para depurar y para las pruebas.
func bump(npc_id: String, _reason: String = "") -> void:
	var cfg: Dictionary = _cfg.get(npc_id, {})
	if cfg.is_empty():
		return
	var flag: String = cfg.get("snap_flag", "")
	if flag != "" and LoopManager.has_knowledge(flag):
		return   # ya saltó este loop
	var count: int = ticks_of(npc_id) + 1
	_ticks[npc_id] = count
	_quiet[npc_id] = 0.0
	var actor: NpcActor = _actor(npc_id)
	if count >= _ticks_to_snap and flag != "":
		_ticks[npc_id] = 0
		LoopManager.gain_knowledge(flag)
		_pending.append(npc_id)
	elif actor != null:
		actor.show_bark(tr(cfg["gesture_key"] if count == 1 else cfg["word_key"]))
		_ticks[npc_id] = mini(count, _ticks_to_snap - 1) if flag != "" else mini(count, 2)


func _process(delta: float) -> void:
	for npc_id: String in _ticks.keys():
		_quiet[npc_id] = float(_quiet.get(npc_id, 0.0)) + delta
		if _quiet[npc_id] >= DECAY_SECONDS and int(_ticks[npc_id]) > 0:
			_ticks[npc_id] = int(_ticks[npc_id]) - 1
			_quiet[npc_id] = 0.0
	if GameManager.state != GameManager.State.PLAYING:
		return
	_track_lingering(delta)
	_try_snap()


func _track_lingering(delta: float) -> void:
	var player: PlayerController = ZoneManager.player
	if player == null:
		return
	for node in get_tree().get_nodes_in_group("npc_actors"):
		var actor := node as NpcActor
		if actor == null or not _cfg.has(actor.npc_id):
			continue
		var near: bool = actor.visible and actor.zone == ZoneManager.current_zone and not actor.is_talking() \
				and (actor.global_position - player.global_position).abs().x < LINGER_RANGE.x \
				and (actor.global_position - player.global_position).abs().y < LINGER_RANGE.y
		if not near:
			_linger[actor.npc_id] = 0.0
			continue
		_linger[actor.npc_id] = float(_linger.get(actor.npc_id, 0.0)) + delta
		if _linger[actor.npc_id] >= LINGER_SECONDS:
			_linger[actor.npc_id] = 0.0
			bump(actor.npc_id, "linger")


## El NPC que se hartó interrumpe: se vuelve y habla (su entrada <npc>_snap).
func _try_snap() -> void:
	if _pending.is_empty() or DialogueManager.is_active:
		return
	var npc_id: String = _pending[0]
	var actor: NpcActor = _actor(npc_id)
	var player: PlayerController = ZoneManager.player
	if actor == null or player == null:
		_pending.pop_front()
		return
	if not actor.visible or actor.zone != ZoneManager.current_zone:
		return   # esperará a que el jugador vuelva a tenerlo a la vista
	var offset: Vector2 = (actor.global_position - player.global_position).abs()
	if offset.x > SNAP_REACH.x or offset.y > SNAP_REACH.y:
		return
	_pending.pop_front()
	DialogueManager.start(npc_id)


func _on_dialogue_started(npc_id: String) -> void:
	if not _cfg.has(npc_id):
		return
	var ended: float = float(_last_talk_end.get(npc_id, -100.0))
	if Time.get_ticks_msec() / 1000.0 - ended < PESTER_SECONDS:
		bump(npc_id, "pester")


func _on_dialogue_ended(npc_id: String) -> void:
	_last_talk_end[npc_id] = Time.get_ticks_msec() / 1000.0


func _actor(npc_id: String) -> NpcActor:
	for node in get_tree().get_nodes_in_group("npc_actors"):
		var actor := node as NpcActor
		if actor != null and actor.npc_id == npc_id:
			return actor
	return null
