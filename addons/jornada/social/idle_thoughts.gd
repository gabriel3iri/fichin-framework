extends Node
## Pensar quieto (data/game.json "idle_thoughts"): si el jugador se queda sin tocar nada un rato y tiene un caso con
## todas sus piezas anotadas sin armar, la cámara se acerca despacio y el personaje piensa en ese caso: así se entera de
## que puede armarlo en el diario sin un cartel de tutorial.
##   - Cuenta segundos reales sin ninguna tecla, clic ni movimiento, con el jugador libre: sin charla, cartel, diario,
##     minijuego ni pausa.
##   - Solo piensa si hay algo que pensar (DeductionSystem, deducciones manuales que no se resuelven solas): cada caso,
##     una vez por jornada, y entre un pensamiento y otro, `cooldown_minutes` de juego.
##   - Cualquier tecla o clic corta el acercamiento de golpe: quien está esperando a ver algo no lo pierde.
##   - El texto: `key_prefix` + id de la deducción si existe en el CSV; si no, `key` con {caso} = el título del caso.

## Lo que dura el acercamiento y la vuelta (segundos reales).
const ZOOM_IN: float = 1.6
const ZOOM_OUT: float = 0.25

var _cfg: Dictionary = {}
var _idle: float = 0.0
var _thought_today: Dictionary = {}   # deducción -> true (esta jornada)
var _last_minute: float = -100000.0
var _focused: bool = false
var _tween: Tween


func _ready() -> void:
	_cfg = GameConfig.value("idle_thoughts", {})
	if _cfg.is_empty():
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS   # el corte del acercamiento tiene que andar aunque algo pause
	LoopManager.loop_started.connect(func(_n: int) -> void: _reset())
	LoopManager.game_reset.connect(_reset)


func _reset() -> void:
	_thought_today.clear()
	_last_minute = -100000.0
	_idle = 0.0
	_unfocus(0.0)


## Cualquier tecla, botón o clic (aunque otro nodo ya lo haya usado) vuelve a empezar la cuenta y corta el acercamiento.
func _touched() -> void:
	_idle = 0.0
	if _focused:
		_unfocus(ZOOM_OUT)


func _process(delta: float) -> void:
	if Input.is_anything_pressed():
		_touched()
		return
	var player: PlayerController = ZoneManager.player
	if not _free(player):
		_idle = 0.0
		return
	if player.velocity.length_squared() > 1.0:
		_idle = 0.0
		return
	_idle += delta / maxf(Engine.time_scale, 0.001)   # segundos reales, aunque el juego vaya acelerado
	if _focused or _idle < float(_cfg.get("after_seconds", 20.0)):
		return
	if TimeManager.minutes - _last_minute < float(_cfg.get("cooldown_minutes", 60)):
		return
	var case_id: String = ready_case()
	if case_id == "":
		return
	_think(player, case_id)


## Un caso con todas sus piezas anotadas, sin armar y sin pensar hoy ("" si no hay).
func ready_case() -> String:
	if not DeductionSystem.manual():
		return ""
	var noted: Array[String] = Cases.clues()
	for def: Dictionary in DeductionSystem.definitions():
		var id: String = def["id"]
		if def.get("auto", false) or _thought_today.has(id) or LoopManager.has_knowledge(id):
			continue
		var all_of: Array = def["all_of"]
		var any_of: Array = def["any_of"]
		if all_of.all(func(f: String) -> bool: return f in noted) \
				and (any_of.is_empty() or any_of.any(func(f: String) -> bool: return f in noted)):
			return id
	return ""


func _think(player: PlayerController, case_id: String) -> void:
	_thought_today[case_id] = true
	_last_minute = TimeManager.minutes
	var seconds: float = float(_cfg.get("seconds", 6.0))
	var own: String = str(_cfg.get("key_prefix", "")) + case_id
	var text: String = tr(own) if own != "" and tr(own) != own else \
			tr(str(_cfg.get("key", ""))).format({"caso": tr(str(DeductionSystem.definition(case_id).get("title_key", case_id)))})
	_focus(player, float(_cfg.get("zoom", 1.3)))
	player.think(text, seconds)
	await get_tree().create_timer(seconds, true, false, true).timeout
	if _focused:
		_unfocus(ZOOM_OUT * 3.0)


func _free(player: PlayerController) -> bool:
	return player != null and player.can_move and not get_tree().paused and not DialogueManager.is_active \
			and not Notices.is_busy() and WorkManager.active_task == ""


func _camera() -> PlayerCamera:
	var player: PlayerController = ZoneManager.player
	return player.get_node_or_null("Camera2D") as PlayerCamera if player != null else null


func _focus(_player: PlayerController, factor: float) -> void:
	var camera: PlayerCamera = _camera()
	if camera == null:
		return
	_focused = true
	_tween_focus(camera, factor, ZOOM_IN)


func _unfocus(seconds: float) -> void:
	_focused = false
	var camera: PlayerCamera = _camera()
	if camera == null:
		return
	if seconds <= 0.0:
		if _tween != null:
			_tween.kill()
		camera.focus = 1.0
		return
	_tween_focus(camera, 1.0, seconds)


func _tween_focus(camera: PlayerCamera, to: float, seconds: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(camera, "focus", to, seconds)
