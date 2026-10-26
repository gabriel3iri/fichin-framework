extends Node
## Habitaciones ajenas (data/private_rooms.json): no se entra a cualquier cuarto "porque uno es el jugador".
##   - Ocupante adentro  -> se GOLPEA; abre (diálogo data/dialogue/door_<ocupante>.json) o dice que no.
##   - Ocupante afuera   -> cerrada con llave: segunda pulsación de E para FORZARLA (lleva unos segundos y minutos de juego).
##     Si alguien en la zona de la puerta lo ve, el intento falla y sube la sospecha.
##   - Si el ocupante vuelve y encuentra al jugador adentro: sospecha y lo echa.
## Todo se olvida al empezar el loop.

const PATH: String = "res://data/private_rooms.json"

var _config: Dictionary = {}
var _permit: Dictionary = {}       # habitación -> true: el ocupante dejó pasar (hasta que el jugador salga)
var _forced: Dictionary = {}       # habitación -> true: cerradura forzada este loop
var _caught: Dictionary = {}       # habitación -> true: ya lo encontraron adentro este loop
var _pending: Dictionary = {}      # habitación -> ms hasta cuando vale la segunda pulsación
var _busy: bool = false
var _check_timer: float = 0.0
var _bar_layer: CanvasLayer
var _bar: ProgressBar


func _ready() -> void:
	_config = GameConfig.read_data(PATH)
	LoopManager.loop_started.connect(func(_n: int) -> void: reset())
	ZoneManager.zone_changed.connect(_on_zone_changed)


func reset() -> void:
	_permit.clear()
	_forced.clear()
	_caught.clear()
	_pending.clear()
	_busy = false


func rooms() -> Dictionary:
	return _config.get("rooms", {})


func setting(key: String, fallback: float) -> float:
	return float(_config.get(key, fallback))


## Regla de la puerta `from_zone` -> `to_zone` si es una habitación ajena; {} si no.
func rule_for(from_zone: String, to_zone: String) -> Dictionary:
	var rule: Dictionary = rooms().get(to_zone, {})
	if rule.is_empty() or rule.get("from", "") != from_zone:
		return {}
	return rule


## ¿Quién está adentro ahora? (el actor del ocupante si su zona es la habitación)
func occupant_inside(room: String) -> NpcActor:
	var rule: Dictionary = rooms().get(room, {})
	for node in get_tree().get_nodes_in_group("npc_actors"):
		var actor := node as NpcActor
		if actor != null and actor.npc_id == rule.get("occupant", "") and actor.zone == room:
			return actor
	return null


## Se llama desde Door.interact() cuando la puerta es de una habitación ajena.
func interact(door: Door, rule: Dictionary) -> void:
	if _busy:
		return
	var room: String = door.target_zone
	if _permit.has(room) or _forced.has(room):
		door.enter()
		return
	_busy = true
	var player: PlayerController = ZoneManager.player
	player.can_move = false
	var entered: bool = false
	if occupant_inside(room) != null:
		entered = await _knock(door, room, rule)
	elif _pending.get(room, 0) > Time.get_ticks_msec():
		entered = await _force(door, room, rule)
	else:
		AudioManager.play_sfx("door_locked", -4.0)
		Toasts.show_key("toast_door_locked_force")
		_pending[room] = Time.get_ticks_msec() + int(setting("retry_window_seconds", 5.0) * 1000.0)
	# Si cruzó la puerta, ZoneManager devuelve el control cuando termina el fundido.
	if is_instance_valid(player) and not entered and not DialogueManager.is_active:
		player.can_move = true
	_busy = false


func _knock(door: Door, room: String, rule: Dictionary) -> bool:
	AudioManager.play_sfx("door_knock", -2.0)
	await get_tree().create_timer(setting("knock_seconds", 1.4)).timeout
	var occupant: String = rule["occupant"]
	var accepts: bool = GameManager.suspicion < int(setting("suspicion_refuse_from", 60.0))
	if not DialogueManager.start("door_" + occupant):
		Toasts.show_key("toast_door_no_answer")
		return false
	await _until_dialogue_ends("door_" + occupant)
	if accepts and occupant_inside(room) != null:
		_permit[room] = true
		door.enter()
		return true
	return false


func _force(door: Door, room: String, rule: Dictionary) -> bool:
	_pending.erase(room)
	AudioManager.play_sfx("door_force", -2.0)
	var duration: float = setting("force_seconds", 2.6)
	_show_bar(true)
	var witness: NpcActor = _witness(rule)
	var seen_at: float = duration * 0.6
	var elapsed: float = 0.0
	while elapsed < duration:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		_bar.value = clampf(elapsed / duration, 0.0, 1.0) * 100.0
		if witness != null and elapsed >= seen_at:
			_show_bar(false)
			witness.show_bark(tr("bark_door_seen"))
			GameManager.add_suspicion(int(setting("suspicion_seen", 10.0)))
			TimeManager.advance_minutes(int(setting("force_minutes", 3.0)))
			AudioManager.play_sfx("door_locked", -2.0)
			return false
	_show_bar(false)
	TimeManager.advance_minutes(int(setting("force_minutes", 3.0)))
	_forced[room] = true
	Toasts.show_key("toast_door_forced")
	door.enter()
	return true


## Alguien que ve la puerta: cualquier personaje de las zonas de testigos (el jugador está en la misma).
func _witness(rule: Dictionary) -> NpcActor:
	var zones: Array = rule.get("witness_zones", [])
	for node in get_tree().get_nodes_in_group("npc_actors"):
		var actor := node as NpcActor
		if actor != null and actor.zone in zones and actor.zone == ZoneManager.current_zone and actor.visible:
			return actor
	return null


func _until_dialogue_ends(npc_id: String) -> void:
	while true:
		var ended: String = await DialogueManager.dialogue_ended
		if ended == npc_id:
			return


func _show_bar(on: bool) -> void:
	if _bar_layer == null:
		_bar_layer = CanvasLayer.new()
		_bar_layer.layer = 60
		add_child(_bar_layer)
		_bar = ProgressBar.new()
		_bar.show_percentage = false
		_bar.custom_minimum_size = Vector2(120, 8)
		_bar.size = Vector2(120, 8)
		_bar.position = Vector2(260, 250)
		_bar_layer.add_child(_bar)
	_bar.value = 0.0
	_bar_layer.visible = on


# ── El ocupante vuelve y encuentra al jugador adentro ────────────────────────
func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer < 0.5:
		return
	_check_timer = 0.0
	var room: String = ZoneManager.current_zone
	if not rooms().has(room) or _permit.has(room) or _caught.has(room):
		return
	var actor: NpcActor = occupant_inside(room)
	if actor == null:
		return
	_caught[room] = true
	actor.show_bark(tr("bark_room_caught"))
	GameManager.add_suspicion(int(setting("suspicion_caught", 10.0)))
	Toasts.show_key("toast_room_caught")
	_permit[room] = true   # ya está enterado: no se repite hasta que el jugador salga


func _on_zone_changed(zone_id: String) -> void:
	# Salir de la habitación cancela el permiso: la próxima vez hay que volver a golpear.
	for room: String in _permit.keys():
		if room != zone_id:
			_permit.erase(room)
