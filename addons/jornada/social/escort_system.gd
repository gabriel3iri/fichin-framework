extends Node
## Escolta (data/escort.json): quien le da el encargo al jugador lo lleva hasta donde tiene que empezar, y el jugador la
## sigue. Sirve para que quien juega por primera vez no tenga que adivinar adónde ir.
##   1. Al ganar el flag de arranque (en Rabenholz, la orden de trabajo, primer día) y terminar la charla, `npc` sale hacia
##      el destino (desvío de NpcActor). Si el jugador se queda atrás, se frena y lo espera; si lo alcanza, sigue.
##   2. Si se atrasa, lo llama a los gritos (frases de `call_keys`). Pasado `nag_after` minutos de juego, vuelve a buscarlo
##      y le habla (`nag_entries`), y retoma el camino. Tras `max_nags` vueltas más, lo lleva ella: `force_entry`, fundido, el
##      jugador aparece en el destino, pasa el tiempo que habría costado el camino y suma sospecha (`force_suspicion`).
##   3. En el destino abre `arrive_entry` (o `arrive_forced_entry` si lo trajo ella) y se queda ahí hasta que su horario
##      la mande a otro lado.
## Mientras hay una charla abierta nada se cuenta.

const PATH: String = "res://data/escort.json"
const TICK: float = 0.5
const RETARGET_EVERY: float = 1.0
## Segundos reales que espera a que se libere (otra charla, un desvío ajeno) antes de darse por vencida.
const START_WAIT: float = 3.0

var _cfg: Dictionary = {}
var _job: Dictionary = {}       # vacío = no hay escolta
var _pending: bool = false      # el flag de arranque ya se ganó: sale apenas se pueda
var _waited: float = 0.0
var _tick: float = 0.0
var _retarget: float = 0.0
var _generation: int = 0        # sube con cada loop o partida nueva: corta lo que estaba esperando


func _ready() -> void:
	_cfg = GameConfig.read_data(PATH)
	if _cfg.is_empty():
		set_process(false)
		return
	LoopManager.knowledge_gained.connect(_on_knowledge_gained)
	LoopManager.loop_started.connect(func(_n: int) -> void: _reset())
	LoopManager.game_reset.connect(_reset)


func is_escorting() -> bool:
	return not _job.is_empty()


func _reset() -> void:
	_generation += 1
	_pending = false
	_release()
	_job.clear()


func _on_knowledge_gained(flag: String) -> void:
	var start: Dictionary = _cfg.get("start", {})
	if flag != str(start.get("flag", "")):
		return
	if start.has("loop_max") and LoopManager.loop_number > int(start["loop_max"]):
		return
	_pending = true
	_waited = 0.0


# ── Arranque ─────────────────────────────────────────────────────────────────
func _try_start(delta: float) -> void:
	if DialogueManager.is_active or Notices.is_busy():
		return   # el cartel y la charla van primero
	var leader: NpcActor = _actor()
	var from_zones: Array = _cfg.get("start", {}).get("from_zones", [])
	if leader == null or leader.zone == ZoneManager.GONE or leader.zone == _destination_zone() \
			or (not from_zones.is_empty() and not leader.zone in from_zones):
		_pending = false   # no está, ya está en el destino o la orden la dio en otro lado: no hay nadie a quien seguir
		return
	if leader.is_talking() or leader.is_on_detour():
		_waited += delta   # otra charla o un desvío ajeno (el de ChatterSystem termina un cuadro después de la charla)
		if _waited > START_WAIT:
			_pending = false
		return
	_pending = false
	_job = {"stage": "lead", "lag_since": -1.0, "nags": 0, "calls": 0, "last_call": -1000.0, "chase_from": -1.0, "entry": ""}
	leader.begin_detour(_destination_zone(), _destination_px())


# ── Seguimiento ──────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_retarget += delta
	_tick += delta
	if _tick < TICK:
		return
	var elapsed: float = _tick
	_tick = 0.0
	if ZoneManager.player == null:
		return
	if _pending:
		_try_start(elapsed)
		return
	if _job.is_empty() or DialogueManager.is_active:
		return
	match _job["stage"]:
		"lead":
			_update_lead()
		"approach":
			_update_approach()


func _update_lead() -> void:
	var leader: NpcActor = _actor()
	if leader == null:
		_job.clear()
		return
	var now: float = TimeManager.minutes
	var distance: float = _distance_to_player(leader)
	var limit: float = float(_cfg.get("resume_px", 80)) if leader.is_held() else float(_cfg.get("follow_px", 130))
	var lagging: bool = distance > limit
	var arrived: bool = leader.zone == _destination_zone() and leader.is_idle()
	if arrived and not lagging and distance <= float(_cfg.get("arrive_px", 70)):
		_arrive(leader, false)
		return
	leader.hold(lagging and not arrived)
	if not lagging:
		_job["lag_since"] = -1.0   # la alcanzó: vuelve a empezar la cuenta del atraso
		return
	if float(_job["lag_since"]) < 0.0:
		_job["lag_since"] = now
	var lag: float = now - float(_job["lag_since"])
	if lag >= float(_cfg.get("call_after", 6)) and now - float(_job["last_call"]) >= float(_cfg.get("call_every", 8)) \
			and leader.zone == ZoneManager.current_zone:
		var keys: Array = _cfg.get("call_keys", [])
		if not keys.is_empty():
			leader.show_bark(tr(str(keys[int(_job["calls"]) % keys.size()])), UiStyle.ACCENT, 2.5)
			_job["calls"] = int(_job["calls"]) + 1
		_job["last_call"] = now
	if lag >= float(_cfg.get("nag_after", 18)):
		_go_find_player(leader)


## Va a buscarlo: primero las vueltas de insistir, y cuando se agotan, la que lo lleva ella.
func _go_find_player(leader: NpcActor) -> void:
	var nag_entries: Array = _cfg.get("nag_entries", [])
	var nags: int = int(_job["nags"])
	if nags < mini(nag_entries.size(), int(_cfg.get("max_nags", 2))):
		_job["entry"] = str(nag_entries[nags])
		_job["forced"] = false
		_job["nags"] = nags + 1
	else:
		_job["entry"] = str(_cfg.get("force_entry", ""))
		_job["forced"] = true
	_job["stage"] = "approach"
	_job["chase_from"] = TimeManager.minutes
	_walk_to_player(leader)


func _update_approach() -> void:
	var leader: NpcActor = _actor()
	if leader == null:
		_job.clear()
		return
	var distance: float = _distance_to_player(leader)
	if distance <= float(_cfg.get("talk_px", 40)):
		_engage(leader)
		return
	if TimeManager.minutes - float(_job["chase_from"]) > float(_cfg.get("chase_minutes", 12)):
		# No la deja acercarse: si era la última vuelta lo lleva igual (sin charla); si no, lo da por insistido y sigue.
		if bool(_job["forced"]):
			_force(leader, false)
		else:
			_resume_lead(leader)
		return
	if leader.zone != ZoneManager.current_zone:
		if leader.is_idle():
			_walk_to_player(leader)   # el jugador cambió de zona mientras tanto
	elif _retarget >= RETARGET_EVERY:
		_retarget = 0.0
		leader.retarget_detour(ZoneManager.player.global_position)


## Va hasta el jugador caminando desde donde está, zona por zona (no aparece en la puerta más cercana a él), y mientras
## camina nadie la aborda: su charla es la que cuenta.
func _walk_to_player(leader: NpcActor) -> void:
	leader.begin_detour(ZoneManager.current_zone, ZoneManager.player.global_position)
	leader.lock_interaction(true)


func _engage(leader: NpcActor) -> void:
	var forced: bool = bool(_job["forced"])
	var npc_id: String = leader.npc_id
	if not DialogueManager.start(npc_id, str(_job["entry"])):
		if forced:
			_force(leader, false)
		else:
			_resume_lead(leader)
		return
	var generation: int = _generation
	DialogueManager.dialogue_ended.connect(func(_id: String) -> void:
		if generation != _generation or _job.is_empty() or not is_instance_valid(leader):
			return
		if forced:
			_force(leader, true)
		else:
			_resume_lead(leader), CONNECT_ONE_SHOT)
	_job["stage"] = "talking"


func _resume_lead(leader: NpcActor) -> void:
	_job["stage"] = "lead"
	_job["lag_since"] = -1.0
	leader.begin_detour(_destination_zone(), _destination_px())


# ── Cuando lo lleva ella ─────────────────────────────────────────────────────
func _force(leader: NpcActor, spoke: bool) -> void:
	_job["stage"] = "forced"
	var generation: int = _generation
	var player: PlayerController = ZoneManager.player
	var zone: String = _destination_zone()
	var cost: int = ceili(ZoneManager.route_length_px(ZoneManager.current_zone, player.global_position, zone, _destination_px())
			/ NpcActor.WALK_SPEED * TimeManager.time_scale) + 1
	if not spoke:
		leader.show_bark(tr(str(_cfg.get("force_bark", ""))), UiStyle.ACCENT, 2.0)
	await ZoneManager.teleport(zone, _player_px())
	if generation != _generation or not is_instance_valid(leader):
		return
	leader.warp(zone, _destination_px())
	TimeManager.advance_minutes(cost)
	GameManager.add_suspicion(int(_cfg.get("force_suspicion", 0)))
	_arrive(leader, true)


# ── Llegada ──────────────────────────────────────────────────────────────────
func _arrive(leader: NpcActor, forced: bool) -> void:
	_job["stage"] = "arrived"
	leader.hold(false)
	var entry: String = str(_cfg.get("arrive_forced_entry" if forced else "arrive_entry", ""))
	if entry == "" or not DialogueManager.start(leader.npc_id, entry):
		_finish(leader)
		return
	var generation: int = _generation
	DialogueManager.dialogue_ended.connect(func(_id: String) -> void:
		if generation == _generation and is_instance_valid(leader):
			_finish(leader), CONNECT_ONE_SHOT)


func _finish(leader: NpcActor) -> void:
	leader.end_detour_in_place()   # se queda en el destino hasta que su horario la mande a otro lado
	_job.clear()


# ── Ayudas ───────────────────────────────────────────────────────────────────
func _release() -> void:
	var leader: NpcActor = _actor()
	if leader != null and not _job.is_empty():
		leader.end_detour()


func _actor() -> NpcActor:
	for node in get_tree().get_nodes_in_group("npc_actors"):
		if node is NpcActor and node.npc_id == _cfg.get("npc", ""):
			return node
	return null


func _distance_to_player(leader: NpcActor) -> float:
	if leader.zone != ZoneManager.current_zone or not leader.visible:
		return INF
	return leader.global_position.distance_to(ZoneManager.player.global_position)


func _destination_zone() -> String:
	return str(_cfg.get("destination", {}).get("zone", ""))


func _destination_px() -> Vector2:
	var tile: Array = _cfg.get("destination", {}).get("tile", [0, 0])
	return ZoneManager.tile_px(Vector2i(int(tile[0]), int(tile[1])))


func _player_px() -> Vector2:
	var tile: Array = _cfg.get("destination", {}).get("player_tile", [0, 0])
	return ZoneManager.tile_px(Vector2i(int(tile[0]), int(tile[1])))
