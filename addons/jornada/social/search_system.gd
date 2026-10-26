extends Node
## Búsqueda del jugador (data/search.json). Nadie aparece por arte de magia: en cada hito horario, si el jugador va
## atrasado con el trabajo, `npc` lo busca, y solo llega adonde alguien pudo haberlo visto (Sightings) y lo dice.
##   1. Toma el avistamiento más reciente con testigo y camina hasta esa zona (desvío de NpcActor, sin perder su horario).
##   2. Si el jugador ya se fue, sigue el rastro del siguiente avistamiento (hasta `max_hops` saltos).
##   3. Si lo ve, lo llama desde lejos, se le acerca y abre su charla con la excusa (SearchSystem arma el texto con
##      DialogueManager.context: «{quien} me avisó que lo vio por {lugar}.» + el aviso del nivel).
##   4. Si el lugar queda fuera de su alcance o es de los que no pisa, manda a un mensajero que sí esté libre.
##   5. Si nadie lo vio, no lo encuentra: queda anotado (flags.lost) y se lo dice en el próximo encuentro.
## El jugador conserva el control: puede esquivarla; si no la deja acercarse en `chase_minutes`, se rinde y la evasión
## suma sospecha. El aviso cuenta aunque no lo encuentre.

const PATH: String = "res://data/search.json"
const TICK: float = 0.5
const RETARGET_EVERY: float = 1.0

var _cfg: Dictionary = {}
var _fired: Dictionary = {}    # índice de hito -> true (este loop)
var _job: Dictionary = {}      # búsqueda en curso; vacío = ninguna
var _resume_level: int = 0     # búsqueda que estaba en curso al guardar: se retoma desde el principio al cargar
var _loaded: Dictionary = {}   # lo leído del guardado; se aplica cuando la carga rápida termina (antes el loop lo vacía)
var _tick: float = 0.0
var _retarget: float = 0.0


func _ready() -> void:
	_cfg = GameConfig.read_data(PATH)
	if _cfg.is_empty():
		set_process(false)
		return
	TimeManager.minute_changed.connect(_on_minute_changed)
	LoopManager.loop_started.connect(func(_n: int) -> void: _reset())
	LoopManager.game_reset.connect(_reset)
	SaveManager.register_section("search", _to_json, func(value: Variant) -> void: _loaded = value if typeof(value) == TYPE_DICTIONARY else {})
	SaveManager.quick_state_applied.connect(_on_quick_state_applied)


func is_searching() -> bool:
	return not _job.is_empty()


func _reset() -> void:
	_stop_actors()
	_job.clear()
	_fired.clear()
	_resume_level = 0


# ── Guardado ─────────────────────────────────────────────────────────────────
## Qué hitos ya se cumplieron y, si había una búsqueda en curso, de qué aviso era. Los NPC no guardan por dónde iban:
## al cargar, la búsqueda arranca de nuevo con los mismos avistamientos (también guardados) y sin repetir el aviso.
func _to_json() -> Dictionary:
	return {"fired": _fired.keys(), "resume_level": int(_job["level"]) if not _job.is_empty() else _resume_level}


func _on_quick_state_applied() -> void:
	_fired.clear()
	for index: Variant in _loaded.get("fired", []):
		_fired[int(index)] = true
	_resume_level = int(_loaded.get("resume_level", 0))
	_loaded = {}


# ── Hitos ────────────────────────────────────────────────────────────────────
func _on_minute_changed(_hour: int, _minute: int) -> void:
	var now: int = TimeManager.now_minutes()
	if _resume_level > 0 and _job.is_empty() and not DialogueManager.is_active and _begin(_resume_level, true):
		_resume_level = 0
	var checkpoints: Array = _cfg.get("checkpoints", [])
	for i in checkpoints.size():
		var checkpoint: Dictionary = checkpoints[i]
		var at: int = TimeManager.parse_clock(checkpoint["time"])
		if _fired.has(i) or now < at:
			continue
		if now > at + int(_cfg.get("window_minutes", 40)):
			_fired[i] = true   # se pasó la ventana sin poder (hablando, o no estaba): se pierde ese aviso
			continue
		if not _job.is_empty() or DialogueManager.is_active:
			continue   # se reintenta al minuto siguiente
		if WorkManager.completed_count() >= int(checkpoint["min_tasks"]):
			_fired[i] = true   # va al día: no hace falta buscarlo
			continue
		if _begin(int(checkpoint["warning"])):
			_fired[i] = true


func _begin(level: int, resumed: bool = false) -> bool:
	var seeker: NpcActor = _actor(_cfg["npc"])
	if seeker == null:
		return true
	if seeker.zone == ZoneManager.GONE or seeker.zone == "" or seeker.is_talking() or seeker.is_on_detour():
		return false
	_job = {"level": level, "hops": 0, "started": TimeManager.now_minutes(), "stage": "walk", "kind": "seen", "who": "",
			"place": "", "target_zone": "", "room": "", "called": false, "chase_from": -1, "actor": null}
	var warned: Array = _cfg["flags"]["warned"]
	if not resumed and level >= 1 and level <= warned.size():
		LoopManager.gain_knowledge(warned[level - 1])
	if seeker.zone == ZoneManager.current_zone and seeker.visible:
		_job["kind"] = "here"
		_job["stage"] = "approach"
		seeker.begin_detour(seeker.zone, ZoneManager.player.global_position)
		return true
	_dispatch(seeker)
	return true


## Elige adónde ir según los avistamientos: caminando, con un mensajero o (si no hay nada) dándolo por perdido.
func _dispatch(seeker: NpcActor) -> void:
	var visited: Array = _job.get("visited", [])
	var sightings: Array = Sightings.recent(int(_cfg.get("witness_window_minutes", 45)), [seeker.npc_id])
	var pick: Dictionary = {}
	for entry: Dictionary in sightings:
		if not _where(entry) in visited:
			pick = entry
			break
	if pick.is_empty():
		_lost(seeker)
		return
	# Adónde fue: quien lo vio irse (`to`) sabe hacia dónde; quien lo vio quieto, solo dónde estaba.
	var zone: String = _where(pick)
	var door_of: Dictionary = _cfg.get("door_of", {})
	var target_zone: String = door_of.get(zone, zone)
	var target_px: Vector2 = _target_px(pick, zone, target_zone)
	var witness: NpcActor = _actor(pick["witnesses"][0])
	_job["kind"] = _cfg.get("zone_tags", {}).get(zone, "seen")
	_job["witness_id"] = pick["witnesses"][0]
	_job["who"] = witness.display_name() if witness != null else ""
	_job["place"] = _place_name(zone)
	_job["room"] = zone if door_of.has(zone) else ""
	_job["target_zone"] = target_zone
	_job["visited"] = visited + [zone]
	var minutes: float = _minutes_to(seeker, target_zone, target_px)
	if target_zone in _cfg.get("no_go", []) or minutes > float(_cfg.get("max_route_minutes", 15)):
		_send_messenger()
		return
	_job["stage"] = "walk"
	seeker.begin_detour(target_zone, target_px)


func _send_messenger() -> void:
	var player: PlayerController = ZoneManager.player
	var best: NpcActor = null
	var best_minutes: float = INF
	for id: String in _cfg.get("messengers", []):
		var candidate: NpcActor = _actor(id)
		if candidate == null or candidate.zone == ZoneManager.GONE or candidate.zone == "" or candidate.is_talking() \
				or candidate.is_on_detour() or candidate.npc_id == _job.get("witness_id", ""):
			continue   # el testigo no se manda a sí mismo: «me dijo que me vio» dicho por él no tiene sentido
		var minutes: float = _minutes_to(candidate, ZoneManager.current_zone, player.global_position)
		if minutes < best_minutes:
			best = candidate
			best_minutes = minutes
	if best == null or best_minutes > float(_cfg.get("messenger_max_route_minutes", 18)):
		_lost(_actor(_cfg["npc"]))
		return
	_job["stage"] = "messenger"
	_job["actor"] = best
	_job["chase_from"] = TimeManager.now_minutes()
	best.begin_detour(ZoneManager.current_zone, player.global_position)


# ── Seguimiento ──────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_tick += delta
	_retarget += delta
	if _tick < TICK:
		return
	_tick = 0.0
	if _job.is_empty() or DialogueManager.is_active or ZoneManager.player == null:
		return
	match _job["stage"]:
		"walk":
			_update_walk()
		"approach":
			_update_approach()
		"messenger":
			_update_messenger()


func _update_walk() -> void:
	var seeker: NpcActor = _actor(_cfg["npc"])
	if seeker == null:
		_job.clear()
		return
	if seeker.zone == ZoneManager.current_zone and seeker.visible:
		_job["stage"] = "approach"   # lo tiene delante (puede haber cruzado a medio camino)
		_job["chase_from"] = TimeManager.now_minutes()
		return
	if TimeManager.now_minutes() - int(_job["started"]) > int(_cfg.get("give_up_minutes", 45)):
		_give_up(seeker)
		return
	if seeker.zone == _job["target_zone"] and seeker.is_idle():
		if _job["room"] != "" and ZoneManager.current_zone == _job["room"]:
			_knock(seeker)   # él está adentro de una habitación: golpea desde la puerta
		else:
			_next_hop(seeker)


func _update_approach() -> void:
	var seeker: NpcActor = _actor(_cfg["npc"])
	var player: PlayerController = ZoneManager.player
	if seeker == null or seeker.zone != ZoneManager.current_zone:
		_next_hop(seeker)   # el jugador cambió de zona
		return
	var distance: float = seeker.global_position.distance_to(player.global_position)
	if not _job["called"] and distance <= float(_cfg.get("call_range", 150)):
		_job["called"] = true
		seeker.show_bark(tr(_cfg.get("call_key", "")), UiStyle.ACCENT, 2.5)
	if distance <= float(_cfg.get("talk_range", 40)):
		_engage(seeker)
		return
	if int(_job["chase_from"]) < 0:
		_job["chase_from"] = TimeManager.now_minutes()
	if TimeManager.now_minutes() - int(_job["chase_from"]) > int(_cfg.get("chase_minutes", 4)):
		_evaded(seeker)
		return
	if _retarget >= RETARGET_EVERY:
		_retarget = 0.0
		seeker.retarget_detour(player.global_position)


func _update_messenger() -> void:
	var messenger: NpcActor = _job["actor"]
	var player: PlayerController = ZoneManager.player
	if messenger == null or not is_instance_valid(messenger):
		_job.clear()
		return
	if TimeManager.now_minutes() - int(_job["chase_from"]) > int(_cfg.get("give_up_minutes", 45)):
		_lost(_actor(_cfg["npc"]))
		messenger.end_detour()
		return
	if messenger.zone != ZoneManager.current_zone:
		if messenger.is_idle():   # el jugador cambió de zona mientras tanto: lo sigue
			messenger.begin_detour(ZoneManager.current_zone, player.global_position)
		return
	var distance: float = messenger.global_position.distance_to(player.global_position)
	if distance <= float(_cfg.get("talk_range", 40)) + 16.0:
		messenger.show_bark(tr(_cfg.get("messenger_key", "")).format({"quien": _job["who"], "lugar": _job["place"]}), UiStyle.ACCENT, 5.0)
		messenger.end_detour()
		_job.clear()
	elif _retarget >= RETARGET_EVERY:
		_retarget = 0.0
		messenger.retarget_detour(player.global_position)


## Llegó al lugar y el jugador ya no está: sigue el rastro del avistamiento siguiente, o lo da por perdido.
func _next_hop(seeker: NpcActor) -> void:
	if seeker == null:
		_job.clear()
		return
	_job["hops"] = int(_job["hops"]) + 1
	if int(_job["hops"]) > int(_cfg.get("max_hops", 3)):
		_lost(seeker)
		return
	seeker.end_detour()
	_dispatch(seeker)


func _engage(seeker: NpcActor) -> void:
	var done: int = WorkManager.completed_count()
	var level: int = int(_job["level"])
	var excuse: String = tr("search_excuse_" + str(_job["kind"])).format({"quien": _job["who"], "lugar": _job["place"]})
	var warning: String = tr("search_warn_%d_%s" % [level, "none" if done == 0 else "some"])
	DialogueManager.context = {"excusa": excuse, "aviso": warning}
	_finish(seeker, level)


## Habla desde el pasillo: el jugador está en su habitación y ella golpea.
func _knock(seeker: NpcActor) -> void:
	AudioManager.play_sfx("door_knock", -2.0)
	_engage(seeker)


func _finish(seeker: NpcActor, level: int) -> void:
	var rule: Dictionary = _cfg.get("third_warning", {})
	if level >= 3 and LoopManager.loop_number >= int(rule.get("loop_min", 2)):
		GameManager.add_suspicion(int(rule.get("suspicion", 0)))   # la tercera vez, desde el segundo día, informa
	_job.clear()
	if not DialogueManager.start(_cfg["npc"], _cfg["entry"]):
		DialogueManager.context = {}
		seeker.end_detour()
		return
	DialogueManager.dialogue_ended.connect(func(_id: String) -> void: seeker.end_detour(), CONNECT_ONE_SHOT)


func _lost(seeker: NpcActor) -> void:
	LoopManager.gain_knowledge(_cfg["flags"]["lost"])
	if seeker != null:
		seeker.end_detour()
	_job.clear()


func _evaded(seeker: NpcActor) -> void:
	seeker.show_bark(tr(_cfg.get("call_key", "")), UiStyle.ACCENT, 2.5)
	GameManager.add_suspicion(int(_cfg.get("evasion_suspicion", 0)))
	_lost(seeker)


func _give_up(seeker: NpcActor) -> void:
	_lost(seeker)


func _stop_actors() -> void:
	var seeker: NpcActor = _actor(_cfg.get("npc", ""))
	if seeker != null:
		seeker.end_detour()
	if _job.get("actor") != null and is_instance_valid(_job["actor"]):
		(_job["actor"] as NpcActor).end_detour()


# ── Ayudas ───────────────────────────────────────────────────────────────────
## La zona a la que apunta un avistamiento: adonde lo vieron irse, o donde lo vieron.
## Adónde camina quien busca, según el avistamiento `pick` (`zone` es donde lo vieron por última vez).
func _target_px(pick: Dictionary, zone: String, target_zone: String) -> Vector2:
	var target_px: Vector2 = pick["pos"]
	if target_zone != zone:   # habitación: va a la puerta, del lado del pasillo
		var door_cell: Vector2i = ZoneManager.exit_cell(target_zone, zone)
		if door_cell.x >= 0:
			target_px = ZoneManager.tile_px(door_cell)
	elif pick.has("to"):
		# Lo vieron irse a `zone`: va a donde se entra. Si no se pasó por una puerta (lo llevaron a la celda), la
		# posición anotada es de la zona vieja: va a cualquier entrada de la nueva.
		var arrival: Variant = ZoneManager.spawn_px(zone, pick["zone"])
		for other: String in ZoneManager.neighbors(zone):
			if arrival != null:
				break
			arrival = ZoneManager.spawn_px(zone, other)
		if arrival != null:
			target_px = arrival
	return target_px


func _where(entry: Dictionary) -> String:
	return str(entry.get("to", entry["zone"]))



func _actor(id: String) -> NpcActor:
	for node in get_tree().get_nodes_in_group("npc_actors"):
		if node is NpcActor and node.npc_id == id:
			return node
	return null


## Minutos de juego que tarda `actor` en llegar caminando a `px` de `zone_id` (INF si no está en el pueblo).
func _minutes_to(actor: NpcActor, zone_id: String, px: Vector2) -> float:
	if actor.zone == ZoneManager.GONE or actor.zone == "":
		return INF
	var length: float = ZoneManager.route_length_px(actor.zone, actor.position, zone_id, px)
	return length / NpcActor.WALK_SPEED * TimeManager.time_scale


func _place_name(zone_id: String) -> String:
	var key: String = _cfg.get("places", {}).get(zone_id, "")
	if key != "":
		return tr(key)
	return tr("zone_" + zone_id).to_lower()
