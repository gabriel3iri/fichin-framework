extends Node
## Escolta (data/escort.json): quien le da el encargo al jugador lo lleva hasta donde tiene que empezar, y el jugador la
## sigue. Sirve para que quien juega por primera vez no tenga que adivinar adónde ir.
##   1. Al ganar el flag de arranque (p. ej. la orden de trabajo) y terminar la charla, `npc` sale hacia
##      el destino (desvío de NpcActor). Si el jugador se queda atrás, se frena y lo espera; si lo alcanza, sigue.
##   2. Si se atrasa, lo llama a los gritos (frases de `call_keys`). Pasado `nag_after` minutos de juego, vuelve a buscarlo
##      y le habla (`nag_entries`), y retoma el camino. Tras `max_nags` vueltas más, lo lleva ella: `force_entry`, fundido, el
##      jugador aparece en el destino, pasa el tiempo que habría costado el camino y suma sospecha (`force_suspicion`).
##   3. En el destino abre `arrive_entry` (o `arrive_forced_entry` si lo trajo ella). Con `tour.stops`, sigue de parada en
##      parada (cada una con su `zone`, `tile`, `player_tile` y la `entry` que dice al llegar; los llamados y las vueltas
##      a buscarlo, con `tour.call_keys`, `tour.nag_entries` y `tour.force_entry` si los hay): un recorrido por todo lo que hay que hacer. En
##      la última se queda hasta que su horario la mande a otro lado.
##   Si el jugador se le adelanta y empieza a trabajar (una tarea hecha o en curso, WorkManager), la escolta ya no tiene
##   sentido: termina sin llamarlo ni ir a buscarlo, y ella sigue a lo suyo.
##   Con `"guided": true` el jugador no se puede ir: camina solo detrás de `npc` (PlayerController.guided) y cruza las
##   puertas y los bordes por donde ella pasó, hasta el destino y cada parada del recorrido; no hay llamados, vueltas ni
##   fundido. Al entrar a una zona con frase en `guided_barks` ({zona: clave}), ella la dice (mostrarle el camino). Si
##   algo lo traba más de `STUCK_SECONDS`, aparece junto a ella. Al terminar el recorrido vuelve a tener el control.
## Mientras hay una charla abierta nada se cuenta.

const PATH: String = "res://data/escort.json"
const TICK: float = 0.5
const RETARGET_EVERY: float = 1.0
## Segundos reales que espera a que se libere (otra charla, un desvío ajeno) antes de darse por vencida.
const START_WAIT: float = 3.0
## Modo guiado: a cuántos px de ella se frena el jugador, cada cuánto recalcula el camino y a cuántos px de la salida la
## cruza; tras cuántos segundos reales sin avanzar se lo pone junto a ella.
const GUIDE_GAP: float = 26.0
const GUIDE_RETARGET: float = 0.25
const GUIDE_EXIT_REACH: float = 6.0
const STUCK_SECONDS: float = 4.0
## Guiado: si ella viene hacia él (sale de un cuarto por donde él entró), él se corre a un costado y espera ahí.
const MAKE_WAY_REACH: float = 30.0
const MAKE_WAY_SECONDS: float = 1.2
## Segundos desde que entra a una zona hasta que ella dice su frase de esa zona.
const BARK_DELAY: float = 0.8

var _cfg: Dictionary = {}
var _job: Dictionary = {}       # vacío = no hay escolta
var _pending: bool = false      # el flag de arranque ya se ganó: sale apenas se pueda
var _waited: float = 0.0
var _tick: float = 0.0
var _retarget: float = 0.0
var _generation: int = 0        # sube con cada loop o partida nueva: corta lo que estaba esperando
var _guide_retarget: float = 0.0
var _stuck: float = 0.0
var _stuck_from: Vector2 = Vector2.ZERO
var _aside_for: float = 0.0


func _ready() -> void:
	_cfg = GameConfig.read_data(PATH)
	if _cfg.is_empty():
		set_process(false)
		return
	LoopManager.knowledge_gained.connect(_on_knowledge_gained)
	LoopManager.loop_started.connect(func(_n: int) -> void: _reset())
	LoopManager.game_reset.connect(_reset)
	ZoneManager.zone_changed.connect(_on_zone_changed)


func is_escorting() -> bool:
	return not _job.is_empty()


## ¿`npc_id` está llevando al jugador ahora? (AnnoyanceSystem: no la fastidia que la siga de cerca)
func is_leading(npc_id: String) -> bool:
	return not _job.is_empty() and npc_id == str(_cfg.get("npc", ""))


## ¿Lleva al jugador sin dejarlo ir (modo guiado)?
func is_guiding() -> bool:
	return not _job.is_empty() and bool(_cfg.get("guided", false))


func _reset() -> void:
	_generation += 1
	_pending = false
	_release()
	_job.clear()
	_set_guided(false)


func _on_knowledge_gained(flag: String) -> void:
	var start: Dictionary = _cfg.get("start", {})
	if flag != str(start.get("flag", "")):
		return
	if start.has("loop_max") and LoopManager.loop_number > int(start["loop_max"]):
		return
	# "unless": con alguno de estos flags ya no hace falta llevarlo (sabe el camino)
	if (start.get("unless", []) as Array).any(func(f: String) -> bool: return LoopManager.has_knowledge(f)):
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
			or (not from_zones.is_empty() and not (leader.zone in from_zones and ZoneManager.current_zone in from_zones)):
		_pending = false   # no está, ya está en el destino o la orden la dio en otro lado: no hay nadie a quien seguir
		return
	if leader.is_talking() or leader.is_on_detour():
		_waited += delta   # otra charla o un desvío ajeno (el de ChatterSystem termina un cuadro después de la charla)
		if _waited > START_WAIT:
			_pending = false
		return
	_pending = false
	_job = {"stage": "lead", "lag_since": -1.0, "nags": 0, "calls": 0, "last_call": -1000.0, "chase_from": -1.0, "entry": "",
		"stop": 0}
	leader.begin_detour(_destination_zone(), _destination_px())
	if bool(_cfg.get("guided", false)):
		_set_guided(true)


# ── Seguimiento ──────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if is_guiding():
		_update_guided(delta)
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
	if _job["stage"] != "arrived" and (WorkManager.completed_count() > 0 or WorkManager.active_task != ""):
		_release()   # ya empezó solo: no hace falta llevarlo ni decirle dónde empieza
		_end_job()
		return
	match _job["stage"]:
		"lead":
			_update_lead()
		"approach":
			_update_approach()


func _update_lead() -> void:
	var leader: NpcActor = _actor()
	if leader == null:
		_end_job()
		return
	var now: float = TimeManager.minutes
	var distance: float = _distance_to_player(leader)
	var limit: float = float(_cfg.get("resume_px", 80)) if leader.is_held() else float(_cfg.get("follow_px", 130))
	var lagging: bool = distance > limit
	if is_guiding() and leader.zone != ZoneManager.current_zone:
		# Guiado, el jugador la sigue por la misma puerta: lo espera solo si le sacó más de una zona.
		lagging = ZoneManager.zone_path(ZoneManager.current_zone, leader.zone).size() > 2
	var arrived: bool = leader.zone == _destination_zone() and leader.is_idle()
	if arrived and not lagging and distance <= float(_cfg.get("arrive_px", 70)):
		_arrive(leader, false)
		return
	leader.hold(lagging and not arrived)
	if is_guiding():
		return   # no se queda atrás por su cuenta: ni llamados ni vueltas a buscarlo
	if not lagging:
		_job["lag_since"] = -1.0   # la alcanzó: vuelve a empezar la cuenta del atraso
		return
	if float(_job["lag_since"]) < 0.0:
		_job["lag_since"] = now
	var lag: float = now - float(_job["lag_since"])
	if lag >= float(_cfg.get("call_after", 6)) and now - float(_job["last_call"]) >= float(_cfg.get("call_every", 8)) \
			and leader.zone == ZoneManager.current_zone:
		var keys: Array = _tour_or("call_keys")
		if not keys.is_empty():
			leader.show_bark(tr(str(keys[int(_job["calls"]) % keys.size()])), UiStyle.ACCENT, 2.5)
			_job["calls"] = int(_job["calls"]) + 1
		_job["last_call"] = now
	if lag >= float(_cfg.get("nag_after", 18)):
		_go_find_player(leader)


## Va a buscarlo: primero las vueltas de insistir, y cuando se agotan, la que lo lleva ella.
func _go_find_player(leader: NpcActor) -> void:
	var nag_entries: Array = _tour_or("nag_entries")
	var nags: int = int(_job["nags"])
	if nags < mini(nag_entries.size(), int(_cfg.get("max_nags", 2))):
		_job["entry"] = str(nag_entries[nags])
		_job["forced"] = false
		_job["nags"] = nags + 1
	else:
		var tour_force: String = str(_cfg.get("tour", {}).get("force_entry", ""))
		_job["entry"] = tour_force if _stop_index() > 0 and tour_force != "" else str(_cfg.get("force_entry", ""))
		_job["forced"] = true
	_job["stage"] = "approach"
	_job["chase_from"] = TimeManager.minutes
	_walk_to_player(leader)


func _update_approach() -> void:
	var leader: NpcActor = _actor()
	if leader == null:
		_end_job()
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
	if _stop_index() > 0:
		entry = str(_stop().get("entry", ""))
	if entry == "" or not DialogueManager.start(leader.npc_id, entry):
		_next_stop(leader)
		return
	var generation: int = _generation
	DialogueManager.dialogue_ended.connect(func(_id: String) -> void:
		if generation == _generation and is_instance_valid(leader) and not _job.is_empty():
			_next_stop(leader), CONNECT_ONE_SHOT)


## Después de cada parada, la siguiente del recorrido (tour.stops); sin más, termina.
func _next_stop(leader: NpcActor) -> void:
	if _stop_index() + 1 >= _stops().size():
		_finish(leader)
		return
	_job["stop"] = _stop_index() + 1
	_job["nags"] = 0
	_job["calls"] = 0
	_resume_lead(leader)


func _finish(leader: NpcActor) -> void:
	leader.end_detour_in_place()   # se queda en el destino hasta que su horario la mande a otro lado
	_job.clear()
	_set_guided(false)


# ── Modo guiado ──────────────────────────────────────────────────────────────
## Termina la escolta antes de tiempo (no hay a quién seguir, ya empezó solo): el jugador vuelve a tener el control.
func _end_job() -> void:
	_job.clear()
	_set_guided(false)


func _set_guided(on: bool) -> void:
	var player: PlayerController = ZoneManager.player
	if player == null:
		return
	player.guided = on
	player.stop_guide()
	_guide_retarget = 0.0
	_aside_for = 0.0
	_stuck = 0.0
	_stuck_from = player.global_position


## Cada cuadro: el jugador camina detrás de ella; si ella ya pasó a otra zona, va hasta la salida que lleva hacia allá
## y la cruza.
func _update_guided(delta: float) -> void:
	var player: PlayerController = ZoneManager.player
	if player == null or DialogueManager.is_active or Journal.is_open or ZoneManager.get("_busy"):
		_stuck = 0.0
		return
	var leader: NpcActor = _actor()
	if leader == null or _job["stage"] != "lead":
		player.stop_guide()
		_stuck = 0.0
		return
	if leader.zone == ZoneManager.current_zone:
		if _aside_for > 0.0:
			_aside_for -= delta   # corrido a un costado: la deja pasar
			return
		if _make_way(player, leader):
			return
		_guide_retarget -= delta
		if _guide_retarget <= 0.0:
			_guide_retarget = GUIDE_RETARGET
			player.guide_to(leader.global_position, GUIDE_GAP)
	else:
		var hops: Array[String] = ZoneManager.zone_path(ZoneManager.current_zone, leader.zone)
		if hops.size() < 2:
			return
		var exit_at: Vector2i = ZoneManager.exit_cell(ZoneManager.current_zone, hops[1])
		if exit_at.x < 0:
			return
		var exit_px: Vector2 = ZoneManager.tile_px(exit_at)
		if player.global_position.distance_to(exit_px) <= GUIDE_EXIT_REACH:
			player.stop_guide()
			_cross(hops[1])
			_stuck = 0.0
			return
		_guide_retarget -= delta
		if _guide_retarget <= 0.0 or not player.is_guide_walking():
			_guide_retarget = GUIDE_RETARGET
			player.guide_to(exit_px)
	_check_stuck(delta, player, leader)


## Si el próximo paso de ella va hacia él, él se corre a la celda libre de al lado (de costado respecto de por donde
## viene ella) y espera ahí MAKE_WAY_SECONDS. Sin eso, ella frena, intenta rodearlo y termina pasando con «Con permiso».
func _make_way(player: PlayerController, leader: NpcActor) -> bool:
	var next: Vector2 = leader.next_step()
	if next == Vector2.INF:
		return false
	var heading: Vector2 = next - leader.global_position
	var to_player: Vector2 = player.global_position - leader.global_position
	if heading.length() < 1.0 or to_player.length() > MAKE_WAY_REACH or heading.normalized().dot(to_player.normalized()) < 0.4:
		return false
	var side: Vector2 = Vector2(-heading.y, heading.x).normalized()
	var here: Vector2i = ZoneManager.cell_of(player.global_position)
	var options: Array[Vector2i] = []
	for s: float in [1.0, -1.0]:
		var step: Vector2i = Vector2i(roundi(side.x * s), roundi(side.y * s))
		options.append(here + step)
		options.append(here + step + Vector2i(roundi(-heading.normalized().x), roundi(-heading.normalized().y)))
	for cell: Vector2i in options:
		if cell == here or ZoneManager.is_cell_solid(ZoneManager.current_zone, cell):
			continue
		var spot: Vector2 = ZoneManager.tile_px(cell)
		if spot.distance_to(next) < 14.0:
			continue   # ahí es justo por donde pasa ella
		player.guide_to(spot, 1.0)
		_aside_for = MAKE_WAY_SECONDS
		_stuck = 0.0
		return true
	return false


## Cruza hacia `target` por donde lo haría a pie: una puerta (fundido) o un borde (deslizamiento).
func _cross(target: String) -> void:
	if ZoneManager.connection(ZoneManager.current_zone, target).get("kind", "door") == "edge":
		ZoneManager.walk_through(target)
	else:
		AudioManager.play_sfx("door_open", -4.0)
		ZoneManager.change_zone(target)


## Si algo lo traba (un personaje en el pasillo, una celda que la grilla da libre y el cuerpo no pasa), no se queda
## caminando contra la pared: aparece junto a ella, con fundido.
func _check_stuck(delta: float, player: PlayerController, leader: NpcActor) -> void:
	if not player.is_guide_walking() or player.global_position.distance_to(_stuck_from) > 4.0:
		_stuck = 0.0
		_stuck_from = player.global_position
		return
	_stuck += delta
	if _stuck < STUCK_SECONDS:
		return
	_stuck = 0.0
	push_warning("EscortSystem: el jugador guiado se trabó en %s %s; pasa junto a %s" % [ZoneManager.current_zone,
			player.global_position, leader.npc_id])
	player.stop_guide()
	ZoneManager.teleport(leader.zone, _free_near(leader.zone, leader.global_position))


func _free_near(zone_id: String, px: Vector2) -> Vector2:
	var cell: Vector2i = ZoneManager.cell_of(px)
	for offset: Vector2i in [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		if not ZoneManager.is_cell_solid(zone_id, cell + offset):
			return ZoneManager.tile_px(cell + offset)
	return px


## Guiado, al entrar a una zona con frase (guided_barks), ella se la dice.
func _on_zone_changed(zone_id: String) -> void:
	if not is_guiding():
		return
	var key: String = str(_cfg.get("guided_barks", {}).get(zone_id, ""))
	if key == "":
		return
	var generation: int = _generation
	await get_tree().create_timer(BARK_DELAY, false).timeout
	var leader: NpcActor = _actor()
	if generation != _generation or not is_guiding() or leader == null or leader.zone != ZoneManager.current_zone \
			or DialogueManager.is_active:
		return
	leader.show_bark(tr(key), UiStyle.ACCENT, 3.5)


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


## El destino y después las paradas del recorrido, en orden.
func _stops() -> Array:
	return [_cfg.get("destination", {})] + (_cfg.get("tour", {}).get("stops", []) as Array)


func _stop_index() -> int:
	return int(_job.get("stop", 0))


func _stop() -> Dictionary:
	return _stops()[clampi(_stop_index(), 0, _stops().size() - 1)]


## Lo del recorrido, si lo tiene, para las paradas después del destino; si no, lo de la escolta.
func _tour_or(field: String) -> Array:
	var tour: Array = _cfg.get("tour", {}).get(field, [])
	return tour if _stop_index() > 0 and not tour.is_empty() else _cfg.get(field, [])


func _destination_zone() -> String:
	return str(_stop().get("zone", ""))


func _destination_px() -> Vector2:
	var tile: Array = _stop().get("tile", [0, 0])
	return ZoneManager.tile_px(Vector2i(int(tile[0]), int(tile[1])))


func _player_px() -> Vector2:
	var tile: Array = _stop().get("player_tile", [0, 0])
	return ZoneManager.tile_px(Vector2i(int(tile[0]), int(tile[1])))
